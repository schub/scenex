defmodule ScenexWeb.GameLive.Simulate do
  @moduledoc """
  Ephemeral dry-run / what-if sandbox for a game definition (Phase 2).

  Builds a pure `Scenex.Engine.Sim` from the game's values, groups and initial
  values, then lets you pick one decision option per group per event and watch
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
        {I18n.t!(@game.name, @locale, default: "Untitled game")}
        <:subtitle>
          <span class="badge badge-sm badge-accent">Dry run</span>
          {@decided}/{@total_slots} decisions made
        </:subtitle>
        <:actions>
          <button type="button" phx-click="reset" class="btn btn-sm btn-ghost">Reset</button>
          <.link navigate={~p"/games/#{@game.id}"} class="btn btn-sm btn-ghost">← Editor</.link>
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
        This game needs at least one value and one group to simulate.
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
        <section :for={%{event: e, options: opts} <- @events} class="space-y-3">
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
                phx-value-event={e.id}
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
    case Authoring.get_game_for_user(id, socket.assigns.current_scope.user) do
      nil ->
        {:ok, socket |> put_flash(:error, "Game not found.") |> push_navigate(to: ~p"/games")}

      {game, role} ->
        {:ok,
         socket
         |> assign(
           game: game,
           role: role,
           locale: game.source_locale,
           locales: Enum.uniq([game.source_locale | @locale_choices]),
           selections: %{},
           page_title: "Dry run — #{I18n.t!(game.name, game.source_locale, default: "Game")}"
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

  def handle_event("toggle_option", %{"event" => eid, "group" => gid, "option" => oid}, socket) do
    key = {eid, gid}

    selections =
      if socket.assigns.selections[key] == oid,
        do: Map.delete(socket.assigns.selections, key),
        else: Map.put(socket.assigns.selections, key, oid)

    {:noreply, socket |> assign(:selections, selections) |> recompute()}
  end

  # ── Building the simulation ───────────────────────────────────────────

  defp load_definition(socket) do
    game = socket.assigns.game
    value_defs = Authoring.list_value_definitions(game)
    groups = Authoring.list_groups(game)

    specs = Enum.map(value_defs, &Authoring.to_value_spec/1)
    group_ids = Enum.map(groups, & &1.id)

    initial =
      for g <- groups, iv <- Authoring.list_group_initial_values(g), reduce: %{} do
        acc ->
          Map.update(
            acc,
            iv.value_definition_id,
            %{g.id => iv.initial},
            &Map.put(&1, g.id, iv.initial)
          )
      end

    events =
      Authoring.list_events(game)
      |> Enum.map(fn e -> %{event: e, options: Authoring.list_decision_options(e)} end)

    per_group_ids =
      for vd <- value_defs, vd.input_scope == :per_group, into: MapSet.new(), do: vd.id

    assign(socket,
      value_defs: value_defs,
      value_index: Map.new(value_defs, &{&1.id, &1}),
      groups: groups,
      events: events,
      per_group_ids: per_group_ids,
      initial_sim: Sim.new(specs, group_ids, initial),
      total_slots: length(events) * length(groups)
    )
  end

  # Fold the current selections onto the fresh sim, in a stable order (events by
  # position, then groups by position) so results don't depend on click order.
  defp recompute(socket) do
    %{
      initial_sim: sim0,
      selections: selections,
      events: events,
      groups: groups,
      per_group_ids: per_group_ids
    } = socket.assigns

    options_by_id =
      for %{options: opts} <- events, o <- opts, into: %{}, do: {o.id, o}

    sim =
      for %{event: e} <- events, g <- groups, reduce: sim0 do
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
      if MapSet.member?(per_group_ids, eff.value_definition_id),
        do: Sim.apply_effect(acc, eff.value_definition_id, gid, eff.delta),
        else: acc
    end)
  end

  # ── View helpers ──────────────────────────────────────────────────────

  defp options_for_group(options, group_id),
    do: Enum.filter(options, &(&1.group_id == group_id))

  defp selected?(selections, event_id, group_id, option_id),
    do: selections[{event_id, group_id}] == option_id

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
        case index[e.value_definition_id] do
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
