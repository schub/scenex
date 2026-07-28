defmodule Scenex.Repo.Migrations.AddDemocracyScoreToScenarios do
  use Ecto.Migration

  def change do
    alter table(:scenarios) do
      add :democracy_formula, :string
      add :democracy_min, :float
      add :democracy_max, :float
    end
  end
end
