defmodule Scenex.Repo.Migrations.AddLocaleToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # The play language for this run; nil falls back to the scenario's
      # source locale at render time.
      add :locale, :string
    end
  end
end
