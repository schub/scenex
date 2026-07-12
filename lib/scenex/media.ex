defmodule Scenex.Media do
  @moduledoc """
  Per-scenario media library: images, short videos, and audio that authors
  embed in content via stable public URLs.

  Bytes go through `Scenex.Media.Storage` (local disk today, swappable);
  rows live in `media_files`. The public URL shape
  `/media/<id>/<filename>` is the permanent contract — it must survive any
  storage-backend change, because authors paste it into markdown snippets.

  Authorization follows the scenario: whoever may edit content may manage
  its media. Callers (LiveViews) enforce that, as everywhere else.
  """

  import Ecto.Query, warn: false

  alias Scenex.Accounts.User
  alias Scenex.Authoring.Scenario
  alias Scenex.Media.{MediaFile, Storage}
  alias Scenex.Repo

  def list_files(%Scenario{} = scenario) do
    Repo.all(
      from f in MediaFile,
        where: f.scenario_id == ^scenario.id,
        order_by: [desc: f.inserted_at]
    )
  end

  def get_file(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(MediaFile, uuid)
      :error -> nil
    end
  end

  @doc """
  Store one upload: insert the row, then persist the bytes. If the bytes
  can't be persisted the row is rolled back, so a listed file always exists.
  """
  def create_file(%Scenario{} = scenario, user, attrs) do
    changeset =
      MediaFile.changeset(%MediaFile{}, %{
        scenario_id: scenario.id,
        filename: attrs.filename,
        content_type: attrs.content_type,
        size: attrs.size,
        uploaded_by_id: user_id(user)
      })

    with {:ok, file} <- Repo.insert(changeset) do
      case Storage.put(key(file), attrs.path) do
        :ok ->
          {:ok, file}

        {:error, reason} ->
          Repo.delete(file)
          {:error, {:storage, reason}}
      end
    end
  end

  def delete_file(%MediaFile{} = file) do
    with {:ok, file} <- Repo.delete(file) do
      Storage.delete(key(file))
      {:ok, file}
    end
  end

  @doc "The storage key: one directory per file id, collision-free."
  def key(%MediaFile{id: id, filename: filename}), do: "#{id}/#{filename}"

  @doc "The stable public path (backend-independent, safe to paste into content)."
  def public_path(%MediaFile{id: id, filename: filename}), do: "/media/#{id}/#{filename}"

  @doc "Coarse kind for icons and embed snippets: `:image` / `:video` / `:audio`."
  def kind(%MediaFile{content_type: "image/" <> _}), do: :image
  def kind(%MediaFile{content_type: "video/" <> _}), do: :video
  def kind(%MediaFile{content_type: "audio/" <> _}), do: :audio

  def max_upload_bytes, do: config()[:max_upload_mb] * 1024 * 1024
  def max_upload_mb, do: config()[:max_upload_mb]

  defp config, do: Application.fetch_env!(:scenex, __MODULE__)

  defp user_id(%User{id: id}), do: id
  defp user_id(nil), do: nil
end
