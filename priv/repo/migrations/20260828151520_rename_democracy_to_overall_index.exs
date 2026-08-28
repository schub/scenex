defmodule Scenex.Repo.Migrations.RenameDemocracyToOverallIndex do
  use Ecto.Migration

  # Renames the scenario's Portugal-specific "Democracy Score" into the
  # scenario-agnostic "Overall Index", in place so existing scenarios keep
  # their ranges, bands and visualization window. Adds an author-set localized
  # name/description for the index.
  #
  # The one thing that can't carry over is the formula itself: the language
  # changed from aggregations over an anonymous list of value globals to keyed
  # arithmetic over value handles (see Scenex.Engine.Index), so every stored
  # formula is blanked and re-entered once per scenario.

  def up do
    rename table(:scenarios), :democracy_formula, to: :overall_index_formula
    rename table(:scenarios), :democracy_min, to: :overall_index_min
    rename table(:scenarios), :democracy_max, to: :overall_index_max
    rename table(:scenarios), :democracy_viz_min, to: :overall_index_viz_min
    rename table(:scenarios), :democracy_viz_max, to: :overall_index_viz_max

    alter table(:scenarios) do
      add :overall_index_name, :map, null: false, default: %{}
      add :overall_index_description, :map, null: false, default: %{}
    end

    rename table(:democracy_bands), to: table(:overall_index_bands)

    execute "UPDATE scenarios SET overall_index_formula = NULL"
  end

  def down do
    rename table(:overall_index_bands), to: table(:democracy_bands)

    alter table(:scenarios) do
      remove :overall_index_name
      remove :overall_index_description
    end

    rename table(:scenarios), :overall_index_viz_max, to: :democracy_viz_max
    rename table(:scenarios), :overall_index_viz_min, to: :democracy_viz_min
    rename table(:scenarios), :overall_index_max, to: :democracy_max
    rename table(:scenarios), :overall_index_min, to: :democracy_min
    rename table(:scenarios), :overall_index_formula, to: :democracy_formula
  end
end
