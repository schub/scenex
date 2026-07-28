defmodule Scenex.Authoring.Page do
  @moduledoc """
  A pre-authored, full-screen scoreboard slide — for before a show starts,
  onboarding, an intermission, sponsor thanks, whatever the room needs
  before or between story beats.

  `content` is markdown (see `Scenex.Play` / `ScenexWeb.Markdown`): plain
  text, and/or a single image or video pulled from the media library. The
  GM picks a page from the console at any time — regardless of session
  status — and it takes over the scoreboard entirely until they switch back
  or clear it; it never affects game state.

  `handle` is the only label a page has — it's never shown to players
  (only `content` is), so it doubles as the GM console's button text with
  no need for a separate, localized display name.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.Scenario

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "pages" do
    field :handle, :string
    field :content, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :scenario, Scenario

    timestamps()
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:scenario_id, :handle, :content, :position])
    |> validate_required([:scenario_id, :handle])
    |> assoc_constraint(:scenario)
    |> unique_constraint(:handle,
      name: :pages_scenario_id_handle_index,
      message: "is already used in this scenario"
    )
  end
end
