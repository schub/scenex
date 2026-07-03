defmodule Scenex.Repo.Migrations.CreatePlaySessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :label, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :game_time_ms, :bigint, null: false, default: 0
      add :clock_started_at, :utc_datetime_usec
      add :ending_id, references(:endings, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:scenario_id])

    # The append-only log: never updated, never deleted (rows only cascade
    # away with their session).
    create table(:session_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sequence, :integer, null: false
      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :game_time_ms, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:session_events, [:session_id, :sequence])
  end
end
