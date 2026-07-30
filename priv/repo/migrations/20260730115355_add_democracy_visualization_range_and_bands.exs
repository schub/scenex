defmodule Scenex.Repo.Migrations.AddDemocracyVisualizationRangeAndBands do
  use Ecto.Migration

  def change do
    alter table(:scenarios) do
      add :democracy_viz_min, :float
      add :democracy_viz_max, :float
    end

    create table(:democracy_bands, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :label, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:democracy_bands, [:scenario_id])
  end
end
