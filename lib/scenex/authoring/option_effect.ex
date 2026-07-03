defmodule Scenex.Authoring.OptionEffect do
  @moduledoc """
  Join: the delta an option applies to one value. Applied to the option's own
  group (a decision only alters the deciding group's values). Written via upsert.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.{DecisionOption, ValueDimension}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "option_effects" do
    field :delta, :float, default: 0.0

    belongs_to :decision_option, DecisionOption
    belongs_to :value_dimension, ValueDimension

    timestamps()
  end

  def changeset(option_effect, attrs) do
    option_effect
    |> cast(attrs, [:decision_option_id, :value_dimension_id, :delta])
    |> validate_required([:decision_option_id, :value_dimension_id, :delta])
    |> assoc_constraint(:decision_option)
    |> assoc_constraint(:value_dimension)
    |> unique_constraint([:decision_option_id, :value_dimension_id])
  end
end
