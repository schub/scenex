defmodule Scenex.Repo.Migrations.AddHandlesToContentEntities do
  use Ecto.Migration

  # A `handle` is a required, non-translated organizational label shown in CMS
  # lists and pickers. (ValueDefinition already has `key` for this purpose.)
  @tables_and_source [
    {"games", "name"},
    {"groups", "name"},
    {"events", "title"},
    {"decision_options", "text"},
    {"labels", "name"}
  ]

  def up do
    for {table, source} <- @tables_and_source do
      alter table(table) do
        add :handle, :string, null: false, default: ""
      end

      # Backfill from existing source-locale content so lists aren't blank.
      execute("""
      UPDATE #{table}
      SET handle = COALESCE(NULLIF(#{source}->>'en', ''), 'untitled')
      WHERE handle = ''
      """)
    end
  end

  def down do
    for {table, _source} <- @tables_and_source do
      alter table(table) do
        remove :handle
      end
    end
  end
end
