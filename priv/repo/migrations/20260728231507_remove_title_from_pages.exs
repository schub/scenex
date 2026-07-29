defmodule Scenex.Repo.Migrations.RemoveTitleFromPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      remove :title, :map, default: %{}
    end
  end
end
