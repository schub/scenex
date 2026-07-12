defmodule Scenex.Repo.Migrations.CreateMediaFiles do
  use Ecto.Migration

  def change do
    create table(:media_files, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :bigint, null: false
      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:media_files, [:scenario_id])
  end
end
