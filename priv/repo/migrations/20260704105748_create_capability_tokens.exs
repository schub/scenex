defmodule Scenex.Repo.Migrations.CreateCapabilityTokens do
  use Ecto.Migration

  def change do
    create table(:capability_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all)
      add :token, :string, null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:capability_tokens, [:token])
    create index(:capability_tokens, [:session_id])
  end
end
