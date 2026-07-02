defmodule Scenex.Authoring.Label do
  @moduledoc """
  An author-defined category for decision options (e.g. "Aggressive" → red).

  Labels are presentation-only metadata — they carry a `color` (and optional
  `icon`) for rendering, but **no deltas** and never touch the simulation. Each
  game defines its own set; another game defines different ones.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @colors [:neutral, :primary, :secondary, :accent, :info, :success, :warning, :error]
  def colors, do: @colors

  schema "labels" do
    field :handle, :string
    field :name, :map, default: %{}
    field :color, Ecto.Enum, values: @colors, default: :neutral
    field :icon, :string
    field :position, :integer, default: 0

    belongs_to :game, Game

    timestamps()
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:game_id, :handle, :name, :color, :icon, :position])
    |> validate_required([:game_id, :handle, :color])
    |> validate_localized_required(:name)
    |> assoc_constraint(:game)
  end
end
