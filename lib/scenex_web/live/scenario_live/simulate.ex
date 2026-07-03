defmodule ScenexWeb.ScenarioLive.Simulate do
  @moduledoc """
  Ephemeral dry-run / what-if sandbox for a scenario definition (Phase 2).

  Builds a pure `Scenex.Engine.Sim` from the scenario's values, groups and initial
  values, then lets you pick one decision option per group per timeline element and watch
  the per-group values and derived globals recompute. Nothing is persisted —
  this is a keyboard sanity-check of the same engine the live sessions use.
  """
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.Engine.Sim
  alias Scenex.I18n

  @locale_choices ~w(en de pt es it)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {I18n.t!(@scenario.name, @locale, default: "Untitled scenario")}
        <:subtitle>
          <span class="badge badge-sm badge-accent">Dry run</span>
          {@decided}/{@total_slots} decisions made
        </:subtitle>
        <:actions>
          <button type="button" phx-click="reset" class="btn btn-sm btn-ghost">Reset</button>
          <.link navigate={~p"/scenarios/#{@scenario.id}"} class="btn btn-sm btn-ghost">
            ← Editor
          </.link>
        </:actions>
      </.header>

      <div class="mt-4 flex items-center gap-2 text-sm">
        <span class="opacity-70">Locale:</span>
        <div class="join">
          <button
            :for={loc <- @locales}
            type="button"
            phx-click="set_locale"
            phx-value-locale={loc}
            class={["btn btn-xs join-item", loc == @locale && "btn-primary"]}
          >
            {loc}
          </button>
        </div>
      </div>

      <p :if={@value_defs == [] or @groups == []} class="mt-6 opacity-70">
        This scenario needs at least one value and one group to simulate.
      </p>

      <%!-- Live board --%>
      <div :if={@value_defs != [] and @groups != []} class="mt-6 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Group</th>
              <th :for={vd <- @value_defs} class="text-right">
                {I18n.t!(vd.name, @locale, default: vd.key)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={g <- @groups}>
              <td class="font-medium whitespace-nowrap">
                {I18n.t!(g.name, @locale, default: g.handle)}
              </td>
              <td
                :for={vd <- @value_defs}
                class={["text-right tabular-nums", cell_class(@sim, vd, g.id)]}
              >
                {fmt_num(Sim.get(@sim, vd.id, g.id))}
              </td>
            </tr>
            <tr class="border-t-2 border-base-300 font-semibold">
              <td class="whitespace-nowrap">Global</td>
              <td :for={vd <- @value_defs} class="text-right tabular-nums">
                {fmt_num(@globals[vd.id])}
                <span class="ml-1 text-xs font-normal opacity-50">{vd.aggregation}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Events & decisions --%>
      <div class="mt-8 space-y-8">
        <section :for={%{timeline_element: e, options: opts} <- @timeline_elements} class="space-y-3">
          <h3 class="text-lg font-semibold">
            <span class="opacity-50">{e.position}.</span>
            {I18n.t!(e.title, @locale, default: e.handle)}
          </h3>

          <div :for={g <- @groups} class="space-y-1">
            <h4 class="text-sm font-medium opacity-70">
              {I18n.t!(g.name, @locale, default: g.handle)}
            </h4>
            <div class="flex flex-wrap gap-2">
              <button
                :for={o <- options_for_group(opts, g.id)}
                type="button"
                phx-click="toggle_option"
                phx-value-timeline_element={e.id}
                phx-value-group={g.id}
                phx-value-option={o.id}
                class={[
                  "btn btn-sm h-auto flex-col items-start gap-0.5 py-2 text-left normal-case",
                  selected?(@selections, e.id, g.id, o.id) && "btn-primary"
                ]}
              >
                <span class="flex items-center gap-1">
                  {o.handle}
                  <span :for={l <- o.labels} class={["badge badge-xs", label_class(l.color)]}>
                    {l.icon || I18n.t!(l.name, @locale, default: "?")}
                  </span>
                </span>
                <span class="text-xs font-normal opacity-70">
                  {fmt_effects(o.effects, @value_index, @locale)}
                </span>
              </button>
              <span :if={options_for_group(opts, g.id) == []} class="text-xs opacity-50">
                No options for this group.
              </span>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Authoring.get_scenario_for_user(id, socket.assigns.current_scope.user) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Scenario not found.") |> push_navigate(to: ~p"/scenarios")}

      {scenario, role} ->
        {:ok,
         socket
         |> assign(
           scenario: scenario,
           role: role,
           locale: scenario.source_locale,
           locales: Enum.uniq([scenario.source_locale | @locale_choices]),
           selections: %{},
           page_title:
             "Dry run — #{I18n.t!(scenario.name, scenario.source_locale, default: "Scenario")}"
         )
         |> load_definition()
         |> recompute()}
    end
  end

  @impl true
  def handle_event("set_locale", %{"locale" => locale}, socket) do
    {:noreply, assign(socket, :locale, locale)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> assign(:selections, %{}) |> recompute()}
  end

  def handle_event(
        "toggle_option",
        %{"timeline_element" => eid, "group" => gid, "option" => oid},
        socket
      ) do
    key = {eid, gid}

    selections =
      if socket.assigns.selections[key] == oid,
        do: Map.delete(socket.assigns.selections, key),
        else: Map.put(socket.assigns.selections, key, oid)

    {:noreply, socket |> assign(:selections, selections) |> recompute()}
  end

  # ── Building the simulation ───────────────────────────────────────────

  defp load_definition(socket) do
    scenario = socket.assigns.scenario
    value_defs = Authoring.list_value_dimensions(scenario)
    groups = Authoring.list_groups(scenario)

    specs = Enum.map(value_defs, &Authoring.to_value_spec/1)
    group_ids = Enum.map(groups, & &1.id)

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

    timeline_elements =
      Authoring.list_timeline_elements(scenario)
      |> Enum.map(fn e -> %{timeline_element: e, options: Authoring.list_decision_options(e)} end)

    per_group_ids =
      for vd <- value_defs, vd.input_scope == :per_group, into: MapSet.new(), do: vd.id

    assign(socket,
      value_defs: value_defs,
      value_index: Map.new(value_defs, &{&1.id, &1}),
      groups: groups,
      timeline_elements: timeline_elements,
      per_group_ids: per_group_ids,
      initial_sim: Sim.new(specs, group_ids, initial),
      total_slots: length(timeline_elements) * length(groups)
    )
  end

  # Fold the current selections onto the fresh sim, in a stable order (elements by
  # position, then groups by position) so results don't depend on click order.
  defp recompute(socket) do
    %{
      initial_sim: sim0,
      selections: selections,
      timeline_elements: timeline_elements,
      groups: groups,
      per_group_ids: per_group_ids
    } = socket.assigns

    options_by_id =
      for %{options: opts} <- timeline_elements, o <- opts, into: %{}, do: {o.id, o}

    sim =
      for %{timeline_element: e} <- timeline_elements, g <- groups, reduce: sim0 do
        acc ->
          case selections[{e.id, g.id}] do
            nil -> acc
            oid -> apply_option(acc, options_by_id[oid], per_group_ids)
          end
      end

    assign(socket, sim: sim, globals: Sim.globals(sim), decided: map_size(selections))
  end

  defp apply_option(sim, %{group_id: gid, effects: effects}, per_group_ids) do
    Enum.reduce(effects, sim, fn eff, acc ->
      if MapSet.member?(per_group_ids, eff.value_dimension_id),
        do: Sim.apply_effect(acc, eff.value_dimension_id, gid, eff.delta),
        else: acc
    end)
  end

  # ── View helpers ──────────────────────────────────────────────────────

  defp options_for_group(options, group_id),
    do: Enum.filter(options, &(&1.group_id == group_id))

  defp selected?(selections, timeline_element_id, group_id, option_id),
    do: selections[{timeline_element_id, group_id}] == option_id

  defp cell_class(sim, vd, group_id) do
    value = Sim.get(sim, vd.id, group_id)

    cond do
      is_nil(value) -> "opacity-40"
      not is_nil(vd.max) and value >= vd.max -> "text-warning font-semibold"
      not is_nil(vd.min) and value <= vd.min -> "text-error font-semibold"
      true -> ""
    end
  end

  defp fmt_num(nil), do: "—"
  defp fmt_num(n) when is_float(n), do: format_float(Float.round(n, 1))
  defp fmt_num(n), do: to_string(n)

  defp format_float(f) do
    if f == trunc(f), do: Integer.to_string(trunc(f)), else: Float.to_string(f)
  end

  defp fmt_effects([], _index, _locale), do: "no effect"

  defp fmt_effects(effects, index, locale) do
    Enum.map_join(effects, ", ", fn e ->
      name =
        case index[e.value_dimension_id] do
          nil -> "?"
          vd -> I18n.t!(vd.name, locale, default: vd.key)
        end

      sign = if e.delta >= 0, do: "+", else: ""
      "#{name} #{sign}#{format_float(e.delta * 1.0)}"
    end)
  end

  defp label_class(:neutral), do: "badge-neutral"
  defp label_class(:primary), do: "badge-primary"
  defp label_class(:secondary), do: "badge-secondary"
  defp label_class(:accent), do: "badge-accent"
  defp label_class(:info), do: "badge-info"
  defp label_class(:success), do: "badge-success"
  defp label_class(:warning), do: "badge-warning"
  defp label_class(:error), do: "badge-error"
  defp label_class(_), do: "badge-neutral"
end
