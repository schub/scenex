defmodule Scenex.Media.Storage.Local do
  @moduledoc """
  Media bytes on the local filesystem, under the configured `:dir`
  (a Docker volume in production). One directory per file id keeps names
  collision-free: `<dir>/<id>/<filename>`.
  """

  @behaviour Scenex.Media.Storage

  @impl true
  def put(key, source_path) do
    dest = path(key)

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         {:ok, _bytes} <- File.copy(source_path, dest) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    # Remove the file's whole <id>/ directory; missing files are fine.
    key |> path() |> Path.dirname() |> File.rm_rf()
    :ok
  end

  @doc "The absolute filesystem path for a key (used by the serving controller)."
  def path(key), do: Path.join(dir(), key)

  defp dir, do: Application.fetch_env!(:scenex, Scenex.Media)[:dir]
end
