defmodule Scenex.Repo.Migrations.AddTaglineToScenarios do
  use Ecto.Migration

  def change do
    alter table(:scenarios) do
      add :tagline, :map, null: false, default: %{}
    end
  end
end
