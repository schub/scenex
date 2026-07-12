defmodule Scenex.Media.MediaFile do
  @moduledoc """
  One uploaded binary (image, video, audio) belonging to a scenario.

  The bytes live in the configured storage under `"<id>/<filename>"`; the row
  is the source of truth for existence, type, and ownership. Only media
  content types are accepted — serving user-supplied HTML or scripts from our
  origin would be an XSS door.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Accounts.User
  alias Scenex.Authoring.Scenario

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "media_files" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :scenario, Scenario
    belongs_to :uploaded_by, User

    timestamps()
  end

  def changeset(media_file, attrs) do
    media_file
    |> cast(attrs, [:scenario_id, :filename, :content_type, :size, :uploaded_by_id])
    |> validate_required([:scenario_id, :filename, :content_type, :size])
    |> update_change(:filename, &sanitize_filename/1)
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_format(:content_type, ~r{^(image|video|audio)/[\w.+-]+$},
      message: "must be an image, video, or audio type"
    )
    # SVG can carry scripts — serving it inline from our origin is XSS.
    |> validate_exclusion(:content_type, ["image/svg+xml"])
    |> validate_number(:size, greater_than: 0)
    |> assoc_constraint(:scenario)
  end

  # The filename becomes part of a disk path and a URL: keep the base name
  # only and reduce it to a safe character set.
  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w.\-]+/u, "_")
  end
end
