defmodule Scenex.Repo.Migrations.AddDesignAlignmentFields do
  use Ecto.Migration

  @moduledoc """
  Phase 2.5 schema additions from the hardened game design:

    * director_notes (localized map) on all content entities
    * decision_options.condition (gate string) and .outcome (sidequest
      success/failure); group_id becomes nullable (election and sidequest
      options belong to no single group)
    * option_effects.group_id — the outcome matrix: nil = "the deciding
      group" (event options), set = explicit target group
    * endings table
  """

  @noted_tables ~w(scenarios value_dimensions groups timeline_elements decision_options labels)a

  def change do
    for tbl <- @noted_tables do
      alter table(tbl) do
        add :director_notes, :map, null: false, default: %{}
      end
    end

    alter table(:decision_options) do
      add :condition, :string
      add :outcome, :string
      modify :group_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:option_effects) do
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all)
    end

    # Uniqueness must respect the group dimension; NULLs are distinct in
    # Postgres unique indexes, so the nil-group ("deciding group") case gets
    # its own partial index.
    drop unique_index(:option_effects, [:decision_option_id, :value_dimension_id])

    create unique_index(:option_effects, [:decision_option_id, :value_dimension_id],
             where: "group_id IS NULL",
             name: :option_effects_option_value_no_group_index
           )

    create unique_index(:option_effects, [:decision_option_id, :value_dimension_id, :group_id],
             where: "group_id IS NOT NULL",
             name: :option_effects_option_value_group_index
           )

    create table(:endings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :handle, :string, null: false
      add :title, :map, null: false, default: %{}
      add :narrative, :map, null: false, default: %{}
      add :director_notes, :map, null: false, default: %{}
      add :condition, :string
      add :priority, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:endings, [:scenario_id, :handle])
  end
end
