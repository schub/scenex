defmodule Scenex.Repo.Migrations.ConsolidateKeysAndNames do
  use Ecto.Migration

  # One vocabulary for every content entity:
  #
  #   * `key`         — the untranslated identifier (was `handle`; value
  #                     dimensions already used `key`)
  #   * `name`        — the short translated label of a thing (was `text` on
  #                     decision options, `label` on value steps and index bands)
  #   * `title`       — the translated headline of content with a body
  #                     (timeline elements, endings — unchanged)
  #   * `description` — the long translated Markdown body (was `narrative` on
  #                     timeline elements and endings)
  #
  # Pure renames: data, and the event log (which stores ids only), carry over.

  @keyed [
    groups: :scenario_id,
    labels: :scenario_id,
    timeline_elements: :scenario_id,
    decision_options: :timeline_element_id,
    endings: :scenario_id,
    pages: :scenario_id
  ]

  def up do
    rename table(:scenarios), :handle, to: :key

    for {table, scope} <- @keyed do
      rename table(table), :handle, to: :key
      execute rename_index(table, scope, "handle", "key")
    end

    rename table(:timeline_elements), :narrative, to: :description
    rename table(:endings), :narrative, to: :description
    rename table(:decision_options), :text, to: :name
    rename table(:value_dimension_steps), :label, to: :name
    rename table(:overall_index_bands), :label, to: :name
  end

  def down do
    rename table(:overall_index_bands), :name, to: :label
    rename table(:value_dimension_steps), :name, to: :label
    rename table(:decision_options), :name, to: :text
    rename table(:endings), :description, to: :narrative
    rename table(:timeline_elements), :description, to: :narrative

    for {table, scope} <- @keyed do
      execute rename_index(table, scope, "key", "handle")
      rename table(table), :key, to: :handle
    end

    rename table(:scenarios), :key, to: :handle
  end

  defp rename_index(table, scope, from, to),
    do: "ALTER INDEX #{table}_#{scope}_#{from}_index RENAME TO #{table}_#{scope}_#{to}_index"
end
