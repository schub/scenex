defmodule Scenex.Repo.Migrations.CreateScenarioInvitations do
  use Ecto.Migration

  def change do
    create table(:scenario_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token, :binary, null: false

      add :scenario_id, references(:scenarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scenario_invitations, [:scenario_id, :email])
    create unique_index(:scenario_invitations, [:token])
  end
end
