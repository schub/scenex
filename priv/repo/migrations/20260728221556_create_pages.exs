defmodule Scenex.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :handle, :string, null: false
      add :title, :map, null: false, default: %{}
      add :content, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:scenario_id, :handle])
  end
end
