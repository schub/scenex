defmodule Scenex.Authoring.ValueDefinition do
  @moduledoc """
  An abstract metric the game tracks (e.g. Stability, Solidarity).

  Projects into the pure engine as a `Scenex.Engine.ValueSpec`: its `aggregation`
  formula derives the global value from per-group values, and `min`/`max` clamp
  per-group values. `input_scope` distinguishes `:per_group` (factions enter
  numbers) from `:per_participant` (individuals vote; e.g. well-being).
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Game, GroupInitialValue}
  alias Scenex.Engine

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @input_scopes [:per_group, :per_participant]
  def input_scopes, do: @input_scopes

  schema "value_definitions" do
    field :key, :string
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :input_scope, Ecto.Enum, values: @input_scopes, default: :per_group
    field :aggregation, :string, default: "avg"
    field :min, :float
    field :max, :float
    field :default_value, :float
    field :position, :integer, default: 0

    belongs_to :game, Game
    has_many :group_initial_values, GroupInitialValue

    timestamps()
  end

  def changeset(value_definition, attrs) do
    value_definition
    |> cast(attrs, [
      :game_id,
      :key,
      :name,
      :description,
      :input_scope,
      :aggregation,
      :min,
      :max,
      :default_value,
      :position
    ])
    |> validate_required([:game_id, :key, :aggregation, :input_scope])
    |> validate_localized_required(:name)
    |> validate_format(:key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be a lowercase slug (letters, digits, underscores)"
    )
    |> validate_aggregation()
    |> validate_min_max()
    |> assoc_constraint(:game)
    |> unique_constraint(:key,
      name: :value_definitions_game_id_key_index,
      message: "is already used in this game"
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
