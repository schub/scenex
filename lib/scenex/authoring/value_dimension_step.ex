defmodule Scenex.Authoring.ValueDimensionStep do
  @moduledoc """
  One step of a per-participant value's readout scale — an emoji at a given
  `position`, ascending from worst (`position` 1) to best.

  A per-participant value is collected as a whole number 1..N by hand count;
  its N steps are that scale, and the emoji standing for the current
  count-weighted mean is shown on the boards. Reproduces (and generalises) the
  old fixed four-smiley well-being scale.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.ValueDimension

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "value_dimension_steps" do
    field :emoji, :string
    field :position, :integer, default: 0

    belongs_to :value_dimension, ValueDimension

    timestamps()
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:value_dimension_id, :emoji, :position])
    |> validate_required([:value_dimension_id, :emoji])
    |> validate_length(:emoji, min: 1, max: 8)
    |> assoc_constraint(:value_dimension)
  end
end
