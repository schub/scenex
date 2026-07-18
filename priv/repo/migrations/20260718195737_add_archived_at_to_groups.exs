defmodule Scenex.Repo.Migrations.AddArchivedAtToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      # Soft delete: an archived group disappears from the editor and from new
      # sessions, but stays loadable so existing sessions replay unchanged.
      add :archived_at, :utc_datetime
    end

    # Handles stay unique among *active* groups only, so a handle can be
    # reused after archiving. Same name keeps the changeset's
    # unique_constraint mapping working.
    drop unique_index(:groups, [:scenario_id, :handle])

    create unique_index(:groups, [:scenario_id, :handle],
             where: "archived_at IS NULL",
             name: :groups_scenario_id_handle_index
           )
  end
end
