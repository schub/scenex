defmodule Scenex.Authoring.GroupInitialValue do
  @moduledoc "Join: a group's starting number for one value. Written via upsert."
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.{Group, ValueDimension}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "group_initial_values" do
    field :initial, :float, default: 0.0

    belongs_to :group, Group
    belongs_to :value_dimension, ValueDimension

    timestamps()
  end

  def changeset(group_initial_value, attrs) do
    group_initial_value
    |> cast(attrs, [:group_id, :value_dimension_id, :initial])
    |> validate_required([:group_id, :value_dimension_id, :initial])
    |> assoc_constraint(:group)
    |> assoc_constraint(:value_dimension)
    |> unique_constraint([:group_id, :value_dimension_id])
  end
end
