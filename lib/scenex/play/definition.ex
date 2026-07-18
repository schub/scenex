defmodule Scenex.Play.Definition do
  @moduledoc """
  An immutable snapshot of a scenario definition, loaded once when a session
  process starts. The projection folds session events against this snapshot,
  so mid-session edits to the scenario don't silently change a running game
  (a restart re-reads the definition — acceptable for the beta).
  """

  alias Scenex.Authoring
  alias Scenex.Authoring.Scenario
  alias Scenex.Engine.Sim

  defstruct scenario_id: nil,
            specs: [],
            value_dimensions: [],
            group_ids: [],
            groups: %{},
            initial: %{},
            elements: %{},
            element_order: [],
            options: %{},
            options_by_element: %{},
            endings: [],
            change_highlight_ms: 30_000

  @type t :: %__MODULE__{}

  @doc """
  Load the snapshot, optionally restricted to a session's group selection
  (`group_ids` nil = the full pool). Excluded groups vanish entirely: no
  board row, no seeded values, no decision options — and effects aimed at
  them no-op because their cells never exist in the sim.
  """
  def load(%Scenario{} = scenario, group_ids \\ nil) do
    value_dimensions = Authoring.list_value_dimensions(scenario)

    # Archived groups stay loadable here: a session that selected (or, for
    # legacy full-pool sessions, historically played with) a since-archived
    # group must replay and render identically forever.
    groups =
      scenario
      |> Authoring.list_groups(include_archived: true)
      |> filter_groups(group_ids)

    selected = MapSet.new(groups, & &1.id)
    elements = Authoring.list_timeline_elements(scenario)

    options_by_element =
      Map.new(elements, fn e ->
        options =
          e
          |> Authoring.list_decision_options()
          |> Enum.filter(&(is_nil(&1.group_id) or MapSet.member?(selected, &1.group_id)))

        {e.id, options}
      end)

    options =
      for {_eid, opts} <- options_by_element, o <- opts, into: %{}, do: {o.id, o}

    initial =
      for g <- groups, iv <- Authoring.list_group_initial_values(g), reduce: %{} do
        acc ->
          Map.update(
            acc,
            iv.value_dimension_id,
            %{g.id => iv.initial},
            &Map.put(&1, g.id, iv.initial)
          )
      end

    %__MODULE__{
      scenario_id: scenario.id,
      specs: Enum.map(value_dimensions, &Authoring.to_value_spec/1),
      value_dimensions: value_dimensions,
      group_ids: Enum.map(groups, & &1.id),
      groups: Map.new(groups, &{&1.id, &1}),
      initial: initial,
      elements: Map.new(elements, &{&1.id, &1}),
      element_order: Enum.map(elements, & &1.id),
      options: options,
      options_by_element: options_by_element,
      endings: Authoring.list_endings(scenario),
      change_highlight_ms: (scenario.change_highlight_seconds || 30) * 1000
    }
  end

  @doc "A fresh sim seeded with the scenario's starting values."
  def initial_sim(%__MODULE__{} = definition) do
    Sim.new(definition.specs, definition.group_ids, definition.initial)
  end

  defp filter_groups(groups, nil), do: groups

  defp filter_groups(groups, group_ids) do
    selected = MapSet.new(group_ids)
    Enum.filter(groups, &MapSet.member?(selected, &1.id))
  end
end
