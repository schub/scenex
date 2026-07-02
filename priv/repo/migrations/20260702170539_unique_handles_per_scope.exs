defmodule Scenex.Repo.Migrations.UniqueHandlesPerScope do
  use Ecto.Migration

  # A handle must be unique within its scope: game for groups/events/labels,
  # event for decision options.
  @scoped [
    {"groups", "game_id"},
    {"events", "game_id"},
    {"labels", "game_id"},
    {"decision_options", "event_id"}
  ]

  def up do
    for {table, scope} <- @scoped do
      # Disambiguate any pre-existing duplicates before enforcing uniqueness.
      execute("""
      UPDATE #{table} t
      SET handle = t.handle || '-' || sub.rn
      FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY #{scope}, handle ORDER BY inserted_at, id
               ) AS rn
        FROM #{table}
      ) sub
      WHERE t.id = sub.id AND sub.rn > 1
      """)

      create unique_index(table, [scope, "handle"])
    end
  end

  def down do
    for {table, scope} <- @scoped do
      drop unique_index(table, [scope, "handle"])
    end
  end
end
