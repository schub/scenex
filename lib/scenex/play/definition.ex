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
            group_ids: [],
            groups: %{},
            initial: %{},
            elements: %{},
            element_order: [],
            options: %{},
            options_by_element: %{},
            endings: []

  @type t :: %__MODULE__{}

  def load(%Scenario{} = scenario) do
    value_dimensions = Authoring.list_value_dimensions(scenario)
    groups = Authoring.list_groups(scenario)
    elements = Authoring.list_timeline_elements(scenario)

    options_by_element =
      Map.new(elements, fn e -> {e.id, Authoring.list_decision_options(e)} end)

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
      group_ids: Enum.map(groups, & &1.id),
      groups: Map.new(groups, &{&1.id, &1}),
      initial: initial,
      elements: Map.new(elements, &{&1.id, &1}),
      element_order: Enum.map(elements, & &1.id),
      options: options,
      options_by_element: options_by_element,
      endings: Authoring.list_endings(scenario)
    }
  end

  @doc "A fresh sim seeded with the scenario's starting values."
  def initial_sim(%__MODULE__{} = definition) do
    Sim.new(definition.specs, definition.group_ids, definition.initial)
  end
end
