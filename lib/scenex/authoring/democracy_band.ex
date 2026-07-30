defmodule Scenex.Authoring.DemocracyBand do
  @moduledoc """
  One labeled band of the Democracy Score's `min`..`max` range — an author
  defines as many as the scenario needs (4, 5, 6, whatever), `position`
  ascending from worst (nearest `min`) to best (nearest `max`).

  The scoreboard only ever shows the *worst* and *best* labels, fixed at
  the two ends of the gauge — never which specific band the current score
  falls in (see `Scenex.Play.Projection`/the display live view). The full
  ordered list still matters for authoring and for the dry-run sandbox,
  which shows the precise current band for testing.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.Scenario

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "democracy_bands" do
    field :label, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :scenario, Scenario

    timestamps()
  end

  def changeset(band, attrs) do
    band
    |> cast(attrs, [:scenario_id, :label, :position])
    |> validate_required([:scenario_id])
    |> validate_localized_required(:label)
    |> assoc_constraint(:scenario)
  end
end
