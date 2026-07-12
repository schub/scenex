defmodule Scenex.Repo.Migrations.AddChangeHighlightSecondsToScenarios do
  use Ecto.Migration

  def change do
    alter table(:scenarios) do
      add :change_highlight_seconds, :integer, null: false, default: 30
    end
  end
end
