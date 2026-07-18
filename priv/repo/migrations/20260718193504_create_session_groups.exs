defmodule Scenex.Repo.Migrations.CreateSessionGroups do
  use Ecto.Migration

  def change do
    # Which of the scenario's group pool plays in this session. No rows means
    # "all groups" (sessions created before this feature). `:restrict` blocks
    # deleting a group from the pool while a show still references it.
    create table(:session_groups, primary_key: false) do
      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :group_id, references(:groups, type: :binary_id, on_delete: :restrict), null: false
    end

    create unique_index(:session_groups, [:session_id, :group_id])
    create index(:session_groups, [:group_id])
  end
end
