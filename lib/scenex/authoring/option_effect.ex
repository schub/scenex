defmodule Scenex.Authoring.OptionEffect do
  @moduledoc """
  The delta an option applies to one value dimension.

  `group_id` is the **outcome matrix** dimension: `nil` means "the deciding
  group" (event options — a decision only alters the deciding group's own
  values); a set `group_id` targets that group explicitly (election and
  sidequest options, whose outcomes may move any groups' values).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.{DecisionOption, Group, ValueDimension}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "option_effects" do
    field :delta, :float, default: 0.0

    belongs_to :decision_option, DecisionOption
    belongs_to :value_dimension, ValueDimension
    belongs_to :group, Group

    timestamps()
  end

  def changeset(option_effect, attrs) do
    option_effect
    |> cast(attrs, [:decision_option_id, :value_dimension_id, :group_id, :delta])
    |> validate_required([:decision_option_id, :value_dimension_id, :delta])
    |> assoc_constraint(:decision_option)
    |> assoc_constraint(:value_dimension)
    |> assoc_constraint(:group)
    |> unique_constraint([:decision_option_id, :value_dimension_id],
      name: :option_effects_option_value_no_group_index
    )
    |> unique_constraint([:decision_option_id, :value_dimension_id, :group_id],
      name: :option_effects_option_value_group_index
    )
  end
end
