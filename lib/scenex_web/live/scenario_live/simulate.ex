defmodule ScenexWeb.ScenarioLive.Simulate do
  @moduledoc """
  Ephemeral dry-run / what-if sandbox for a scenario definition (Phase 2).

  Builds a pure `Scenex.Engine.Sim` from the scenario's values, groups and
  initial values, then walks the timeline: pick each group's option on events,
  declare election winners (outcome matrices apply), adjudicate sidequests
  (success/failure bundles apply), watch gates lock and unlock, and see which
  endings the final board recommends. Nothing is persisted — this is a
  keyboard sanity-check of the same engine the live sessions use.

  Gates are evaluated against the state *before* their element (elements by
  `position`), mirroring live-play semantics: earlier decisions open or close
  later paths, and an element's own selections never gate itself.
  """
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.Engine.{Condition, Sim}
  alias Scenex.I18n

  @locale_choices Scenex.I18n.locales()

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

      <%!-- Timeline --%>
      <div class="mt-8 space-y-8">
        <section :for={%{timeline_element: e, options: opts} <- @timeline_elements} class="space-y-3">
          <h3 class="text-lg font-semibold">
            <span class="opacity-50">{e.position}.</span>
            {I18n.t!(e.title, @locale, default: e.handle)}
            <span class="badge badge-sm ml-1">{e.kind}</span>
          </h3>

          <%!-- Event: each group picks --%>
          <div :for={g <- @groups} :if={e.kind == :event} class="space-y-1">
            <h4 class="text-sm font-medium opacity-70">
              {I18n.t!(g.name, @locale, default: g.handle)}
            </h4>
            <div class="flex flex-wrap gap-2">
              <.sim_option
                :for={o <- options_for_group(opts, g.id)}
                option={o}
                selected={@selections[{e.id, g.id}] == o.id}
                locked={MapSet.member?(@locked, o.id)}
                slot_value={g.id}
                element_id={e.id}
                locale={@locale}
                value_index={@value_index}
                groups_index={@groups_index}
              />
              <span :if={options_for_group(opts, g.id) == []} class="text-xs opacity-50">
                No options for this group.
              </span>
            </div>
          </div>

          <%!-- Election: declare the winner --%>
          <div :if={e.kind == :election} class="space-y-1">
            <h4 class="text-sm font-medium opacity-70">
              All players vote — declare the winning option:
            </h4>
            <div class="flex flex-wrap gap-2">
              <.sim_option
                :for={o <- opts}
                option={o}
                selected={@selections[{e.id, :winner}] == o.id}
                locked={MapSet.member?(@locked, o.id)}
                slot_value="winner"
                element_id={e.id}
                locale={@locale}
                value_index={@value_index}
                groups_index={@groups_index}
              />
              <span :if={opts == []} class="text-xs opacity-50">No ballot options.</span>
            </div>
          </div>

          <%!-- Sidequest: adjudicate --%>
          <div :if={e.kind == :sidequest} class="space-y-1">
            <h4 class="text-sm font-medium opacity-70">GM adjudicates the outcome:</h4>
            <div class="flex flex-wrap gap-2">
              <.sim_option
                :for={o <- Enum.sort_by(opts, &(&1.outcome != :success))}
                option={o}
                selected={@selections[{e.id, :outcome}] == o.id}
                locked={false}
                slot_value="outcome"
                element_id={e.id}
                locale={@locale}
                value_index={@value_index}
                groups_index={@groups_index}
              />
              <span :if={opts == []} class="text-xs opacity-50">No outcomes defined.</span>
            </div>
          </div>
        </section>
      </div>

      <%!-- Endings --%>
      <section :if={@endings != []} class="mt-10 space-y-3">
        <h3 class="text-lg font-semibold">Endings</h3>
        <p class="text-xs opacity-60">
          Evaluated against the current board — recommendations only; the GM picks.
        </p>
        <ul class="space-y-1">
          <li
            :for={ending <- @endings}
            class={[
              "flex flex-wrap items-center gap-2 rounded bg-base-200 px-3 py-2",
              @ending_status[ending.id] == :not_matching && "opacity-50"
            ]}
          >
            <span class="font-medium">{ending.handle}</span>
            <span class="text-sm opacity-70">
              — {I18n.t!(ending.title, @locale, default: "—")}
            </span>
            <span :if={ending.condition} class="badge badge-xs font-mono">
              {ending.condition}
            </span>
            <span class={["badge badge-sm ml-auto", ending_badge(@ending_status[ending.id])]}>
              {ending_text(@ending_status[ending.id])}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :option, :map, required: true
  attr :selected, :boolean, required: true
  attr :locked, :boolean, required: true
  attr :slot_value, :string, required: true
  attr :element_id, :string, required: true
  attr :locale, :string, required: true
  attr :value_index, :map, required: true
  attr :groups_index, :map, required: true

  defp sim_option(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_option"
      phx-value-timeline_element={@element_id}
      phx-value-slot={@slot_value}
      phx-value-option={@option.id}
      disabled={@locked and not @selected}
      class={[
        "btn btn-sm h-auto flex-col items-start gap-0.5 py-2 text-left normal-case",
        @selected && "btn-primary",
        (@locked and not @selected) && "btn-disabled opacity-60"
      ]}
    >
      <span class="flex items-center gap-1">
        <span :if={@option.outcome} class="badge badge-xs badge-ghost">{@option.outcome}</span>
        {@option.handle}
        <span :for={l <- @option.labels} class={["badge badge-xs", label_class(l.color)]}>
          {l.icon || I18n.t!(l.name, @locale, default: "?")}
        </span>
      </span>
      <span class="text-xs font-normal opacity-70">
        {fmt_effects(@option.effects, @value_index, @groups_index, @locale)}
      </span>
      <span :if={@option.condition} class="text-xs font-normal font-mono opacity-60">
        {if @locked, do: "🔒", else: "✓"} {@option.condition}
      </span>
    </button>
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
        %{"timeline_element" => eid, "slot" => slot, "option" => oid},
        socket
      ) do
    key = {eid, slot_term(slot)}

    selections =
      if socket.assigns.selections[key] == oid,
        do: Map.delete(socket.assigns.selections, key),
        else: Map.put(socket.assigns.selections, key, oid)

    {:noreply, socket |> assign(:selections, selections) |> recompute()}
  end

  # Election winners and sidequest outcomes use atom slots so they can never
  # collide with a group id.
  defp slot_term("winner"), do: :winner
  defp slot_term("outcome"), do: :outcome
  defp slot_term(group_id), do: group_id

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

    total_slots =
      Enum.reduce(timeline_elements, 0, fn %{timeline_element: e}, acc ->
        case e.kind do
          :event -> acc + length(groups)
          _one_decision -> acc + 1
        end
      end)

    assign(socket,
      value_defs: value_defs,
      value_index: Map.new(value_defs, &{&1.id, &1}),
      groups: groups,
      groups_index: Map.new(groups, &{&1.id, &1}),
      timeline_elements: timeline_elements,
      endings: Authoring.list_endings(scenario),
      per_group_ids: per_group_ids,
      initial_sim: Sim.new(specs, group_ids, initial),
      total_slots: total_slots
    )
  end

  # Fold the current selections onto the fresh sim in timeline order, keeping
  # the state *before* each element for gate evaluation.
  defp recompute(socket) do
    %{
      initial_sim: sim0,
      selections: selections,
      timeline_elements: timeline_elements,
      groups: groups,
      value_defs: value_defs,
      per_group_ids: per_group_ids,
      endings: endings
    } = socket.assigns

    {sim, sims_before} =
      Enum.reduce(timeline_elements, {sim0, %{}}, fn %{timeline_element: e, options: opts},
                                                     {acc, before_map} ->
        before_map = Map.put(before_map, e.id, acc)

        acc =
          Enum.reduce(slots_for(e, groups), acc, fn slot, s ->
            with oid when not is_nil(oid) <- selections[{e.id, slot}],
                 %{} = option <- Enum.find(opts, &(&1.id == oid)) do
              apply_option(s, option, per_group_ids)
            else
              _ -> s
            end
          end)

        {acc, before_map}
      end)

    locked = locked_options(timeline_elements, sims_before, value_defs)
    globals = Sim.globals(sim)

    ending_status =
      Map.new(endings, fn ending ->
        {ending.id, ending_status(ending, global_context(value_defs, globals))}
      end)

    assign(socket,
      sim: sim,
      globals: globals,
      locked: locked,
      ending_status: ending_status,
      decided: map_size(selections)
    )
  end

  defp slots_for(%{kind: :event}, groups), do: Enum.map(groups, & &1.id)
  defp slots_for(%{kind: :election}, _groups), do: [:winner]
  defp slots_for(%{kind: :sidequest}, _groups), do: [:outcome]

  # An effect targets its explicit group (outcome matrices) or falls back to
  # the option's own deciding group (event options).
  defp apply_option(sim, %{group_id: own_group_id, effects: effects}, per_group_ids) do
    Enum.reduce(effects, sim, fn eff, acc ->
      target = eff.group_id || own_group_id

      if target && MapSet.member?(per_group_ids, eff.value_dimension_id),
        do: Sim.apply_effect(acc, eff.value_dimension_id, target, eff.delta),
        else: acc
    end)
  end

  # ── Gates ─────────────────────────────────────────────────────────────

  defp locked_options(timeline_elements, sims_before, value_defs) do
    for %{timeline_element: e, options: opts} <- timeline_elements,
        option <- opts,
        option.condition,
        gate_closed?(option, sims_before[e.id], value_defs),
        into: MapSet.new(),
        do: option.id
  end

  defp gate_closed?(option, sim_before, value_defs) do
    context = condition_context(option, sim_before, value_defs)

    case Condition.evaluate(option.condition, context) do
      {:ok, false} -> true
      # Fail-open: an unevaluable gate never blocks (the GM disposes anyway).
      _ -> false
    end
  end

  defp condition_context(option, sim, value_defs) do
    context = %{global: global_context(value_defs, Sim.globals(sim))}

    case option.group_id do
      nil ->
        context

      group_id ->
        self_values =
          Map.new(
            for vd <- value_defs, is_number(Sim.get(sim, vd.id, group_id)) do
              {vd.key, Sim.get(sim, vd.id, group_id)}
            end
          )

        Map.put(context, :self, self_values)
    end
  end

  defp global_context(value_defs, globals) do
    Map.new(for vd <- value_defs, is_number(globals[vd.id]), do: {vd.key, globals[vd.id]})
  end

  # ── Endings ───────────────────────────────────────────────────────────

  defp ending_status(%{condition: nil}, _global_context), do: :open

  defp ending_status(%{condition: condition}, global_context) do
    case Condition.evaluate(condition, %{global: global_context}) do
      {:ok, true} -> :recommended
      {:ok, false} -> :not_matching
      {:error, _} -> :open
    end
  end

  defp ending_badge(:recommended), do: "badge-success"
  defp ending_badge(:not_matching), do: "badge-ghost"
  defp ending_badge(_), do: "badge-ghost"

  defp ending_text(:recommended), do: "recommended"
  defp ending_text(:not_matching), do: "not matching"
  defp ending_text(_), do: "no condition"

  # ── View helpers ──────────────────────────────────────────────────────

  defp options_for_group(options, group_id),
    do: Enum.filter(options, &(&1.group_id == group_id))

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

  defp fmt_effects([], _value_index, _groups_index, _locale), do: "no effect"

  defp fmt_effects(effects, value_index, groups_index, locale) do
    Enum.map_join(effects, ", ", fn e ->
      name =
        case value_index[e.value_dimension_id] do
          nil -> "?"
          vd -> I18n.t!(vd.name, locale, default: vd.key)
        end

      prefix =
        case e.group_id && groups_index[e.group_id] do
          nil -> ""
          g -> I18n.t!(g.name, locale, default: g.handle) <> ": "
        end

      sign = if e.delta >= 0, do: "+", else: ""
      "#{prefix}#{name} #{sign}#{format_float(e.delta * 1.0)}"
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
