defmodule Scenex.Authoring.ValueDimension do
  @moduledoc """
  An abstract metric the scenario tracks (e.g. Stability, Solidarity).

  Projects into the pure engine as a `Scenex.Engine.ValueSpec`: its `aggregation`
  formula derives the global value from per-group values, and `min`/`max` clamp
  per-group values. `input_scope` distinguishes `:per_group` (factions enter
  numbers) from `:per_participant` (individuals vote; e.g. well-being).
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Scenario, GroupInitialValue}
  alias Scenex.Engine

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @input_scopes [:per_group, :per_participant]
  def input_scopes, do: @input_scopes

  schema "value_dimensions" do
    field :key, :string
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :input_scope, Ecto.Enum, values: @input_scopes, default: :per_group
    field :aggregation, :string, default: "avg"
    field :min, :float
    field :max, :float
    field :default_value, :float
    field :position, :integer, default: 0

    belongs_to :scenario, Scenario
    has_many :group_initial_values, GroupInitialValue

    timestamps()
  end

  def changeset(value_dimension, attrs) do
    value_dimension
    |> cast(attrs, [
      :scenario_id,
      :key,
      :name,
      :description,
      :director_notes,
      :input_scope,
      :aggregation,
      :min,
      :max,
      :default_value,
      :position
    ])
    |> validate_required([:scenario_id, :key, :aggregation, :input_scope])
    |> validate_localized_required(:name)
    |> validate_format(:key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be a lowercase slug (letters, digits, underscores)"
    )
    |> clear_bounds_for_participant()
    |> validate_aggregation()
    |> validate_min_max()
    |> assoc_constraint(:scenario)
    |> unique_constraint(:key,
      name: :value_dimensions_scenario_id_key_index,
      message: "is already used in this scenario"
    )
  end

  defp validate_aggregation(changeset) do
    validate_change(changeset, :aggregation, fn :aggregation, formula ->
      case Engine.validate_formula(formula) do
        :ok -> []
        {:error, reason} -> [aggregation: "is not a valid formula (#{inspect(reason)})"]
      end
    end)
  end

  # min/max/default clamp per-group values; per-participant values are never
  # clamped by the engine, so bounds are meaningless there — drop them.
  defp clear_bounds_for_participant(changeset) do
    if get_field(changeset, :input_scope) == :per_participant do
      changeset
      |> put_change(:min, nil)
      |> put_change(:max, nil)
      |> put_change(:default_value, nil)
    else
      changeset
    end
  end

  defp validate_min_max(changeset) do
    min = get_field(changeset, :min)
    max = get_field(changeset, :max)

    if is_number(min) and is_number(max) and min > max do
      add_error(changeset, :max, "must be greater than or equal to min")
    else
      changeset
    end
  end
end
