defmodule Scenex.Repo.Migrations.RenameDomainToMatchDesign do
  use Ecto.Migration

  @moduledoc """
  Align the schema with the game design document's vocabulary:

    * games            -> scenarios          (a game definition IS a scenario)
    * events           -> timeline_elements  (an "event" is one KIND of element)
    * value_definitions -> value_dimensions
    * game_id / event_id / value_definition_id columns accordingly

  Postgres does not rename indexes or constraints with their tables, and our
  changesets reference index names (unique_constraint) while assoc_constraint
  derives fkey names from current column names — so those are renamed too.
  """

  @tables [
    {"games", "scenarios"},
    {"game_memberships", "scenario_memberships"},
    {"value_definitions", "value_dimensions"},
    {"events", "timeline_elements"}
  ]

  # {table (new name), old column, new column}
  @columns [
    {"scenario_memberships", "game_id", "scenario_id"},
    {"value_dimensions", "game_id", "scenario_id"},
    {"groups", "game_id", "scenario_id"},
    {"group_initial_values", "value_definition_id", "value_dimension_id"},
    {"timeline_elements", "game_id", "scenario_id"},
    {"labels", "game_id", "scenario_id"},
    {"decision_options", "event_id", "timeline_element_id"},
    {"option_effects", "value_definition_id", "value_dimension_id"}
  ]

  @indexes [
    {"game_memberships_game_id_user_id_index", "scenario_memberships_scenario_id_user_id_index"},
    {"game_memberships_user_id_index", "scenario_memberships_user_id_index"},
    {"value_definitions_game_id_key_index", "value_dimensions_scenario_id_key_index"},
    {"groups_game_id_index", "groups_scenario_id_index"},
    {"groups_game_id_handle_index", "groups_scenario_id_handle_index"},
    {"group_initial_values_group_id_value_definition_id_index",
     "group_initial_values_group_id_value_dimension_id_index"},
    {"group_initial_values_value_definition_id_index",
     "group_initial_values_value_dimension_id_index"},
    {"events_game_id_index", "timeline_elements_scenario_id_index"},
    {"events_game_id_handle_index", "timeline_elements_scenario_id_handle_index"},
    {"labels_game_id_index", "labels_scenario_id_index"},
    {"labels_game_id_handle_index", "labels_scenario_id_handle_index"},
    {"decision_options_event_id_index", "decision_options_timeline_element_id_index"},
    {"decision_options_event_id_handle_index",
     "decision_options_timeline_element_id_handle_index"},
    {"option_effects_decision_option_id_value_definition_id_index",
     "option_effects_decision_option_id_value_dimension_id_index"},
    {"option_effects_value_definition_id_index", "option_effects_value_dimension_id_index"}
  ]

  # {table (new name), old constraint, new constraint}
  @constraints [
    {"scenarios", "games_pkey", "scenarios_pkey"},
    {"scenario_memberships", "game_memberships_pkey", "scenario_memberships_pkey"},
    {"scenario_memberships", "game_memberships_game_id_fkey",
     "scenario_memberships_scenario_id_fkey"},
    {"scenario_memberships", "game_memberships_user_id_fkey",
     "scenario_memberships_user_id_fkey"},
    {"value_dimensions", "value_definitions_pkey", "value_dimensions_pkey"},
    {"value_dimensions", "value_definitions_game_id_fkey", "value_dimensions_scenario_id_fkey"},
    {"groups", "groups_game_id_fkey", "groups_scenario_id_fkey"},
    {"group_initial_values", "group_initial_values_value_definition_id_fkey",
     "group_initial_values_value_dimension_id_fkey"},
    {"timeline_elements", "events_pkey", "timeline_elements_pkey"},
    {"timeline_elements", "events_game_id_fkey", "timeline_elements_scenario_id_fkey"},
    {"labels", "labels_game_id_fkey", "labels_scenario_id_fkey"},
    {"decision_options", "decision_options_event_id_fkey",
     "decision_options_timeline_element_id_fkey"},
    {"option_effects", "option_effects_value_definition_id_fkey",
     "option_effects_value_dimension_id_fkey"}
  ]

  def up do
    for {old, new} <- @tables, do: rename(table(old), to: table(new))

    for {tbl, old, new} <- @columns,
        do: rename(table(tbl), String.to_atom(old), to: String.to_atom(new))

    for {old, new} <- @indexes, do: execute("ALTER INDEX #{old} RENAME TO #{new}")

    for {tbl, old, new} <- @constraints,
        do: execute("ALTER TABLE #{tbl} RENAME CONSTRAINT #{old} TO #{new}")
  end

  def down do
    for {tbl, old, new} <- @constraints,
        do: execute("ALTER TABLE #{tbl} RENAME CONSTRAINT #{new} TO #{old}")

    for {old, new} <- @indexes, do: execute("ALTER INDEX #{new} RENAME TO #{old}")

    for {tbl, old, new} <- @columns,
        do: rename(table(tbl), String.to_atom(new), to: String.to_atom(old))

    for {old, new} <- @tables, do: rename(table(new), to: table(old))
  end
end
