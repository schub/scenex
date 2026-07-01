defmodule Scenex.Repo.Migrations.CreateAuthoringDefinition do
  use Ecto.Migration

  def change do
    # --- Game (the definition) + authoring membership -----------------------

    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :map, null: false, default: %{}
      add :description, :map, null: false, default: %{}
      add :source_locale, :string, null: false, default: "en"
      add :visibility, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create table(:game_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_memberships, [:game_id, :user_id])
    create index(:game_memberships, [:user_id])

    # --- Values + groups ----------------------------------------------------

    create table(:value_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :name, :map, null: false, default: %{}
      add :description, :map, null: false, default: %{}
      add :input_scope, :string, null: false, default: "per_group"
      add :aggregation, :string, null: false, default: "avg"
      add :min, :float
      add :max, :float
      add :default_value, :float
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:value_definitions, [:game_id, :key])

    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :map, null: false, default: %{}
      add :description, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:groups, [:game_id])

    create table(:group_initial_values, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      add :value_definition_id,
          references(:value_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :initial, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:group_initial_values, [:group_id, :value_definition_id])
    create index(:group_initial_values, [:value_definition_id])

    # --- Timeline: events, options, effects ---------------------------------

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :map, null: false, default: %{}
      add :narrative, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0
      add :kind, :string, null: false, default: "event"
      add :trigger, :string, null: false, default: "manual"
      add :deadline_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:game_id])

    create table(:labels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :map, null: false, default: %{}
      add :color, :string, null: false, default: "neutral"
      add :icon, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:labels, [:game_id])

    create table(:decision_options, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :text, :map, null: false, default: %{}
      add :is_default, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:decision_options, [:event_id])
    create index(:decision_options, [:group_id])

    create table(:option_effects, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :decision_option_id,
          references(:decision_options, type: :binary_id, on_delete: :delete_all),
          null: false

      add :value_definition_id,
          references(:value_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :delta, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:option_effects, [:decision_option_id, :value_definition_id])
    create index(:option_effects, [:value_definition_id])

    # Pure join (composite PK, no timestamps) so many_to_many can manage it.
    create table(:decision_option_labels, primary_key: false) do
      add :decision_option_id,
          references(:decision_options, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :label_id, references(:labels, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true
    end

    create index(:decision_option_labels, [:label_id])
  end
end
