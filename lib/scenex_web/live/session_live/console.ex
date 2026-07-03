defmodule ScenexWeb.SessionLive.Console do
  @moduledoc """
  The GM console — running one live session (Layer 3).

  Everything here is a command to the session process: start/pause/resume/end,
  trigger timeline elements, enter group decisions, resolve elections from a
  hand-count tally, adjudicate sidequests, and finally pick an ending from the
  recommendations. The board updates live via PubSub; a 1s tick keeps the game
  clock and deadline countdowns moving. Corrections are just re-entry (last
  wins) — click a different option and the board recomputes.
  """
  use ScenexWeb, :live_view

  alias Scenex.{Authoring, Play}
  alias Scenex.Engine.{Condition, Sim}
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@session.label}
        <:subtitle>
          <span class="badge badge-sm badge-accent">GM console</span>
          <span class={["badge badge-sm", status_badge(@snap.status)]}>{@snap.status}</span>
          <span class="ml-2 font-mono tabular-nums">{fmt_clock(@snap.game_time_ms)}</span>
        </:subtitle>
        <:actions>
          <button
            :if={@snap.status == :draft}
            phx-click="start"
            class="btn btn-sm btn-primary"
            data-confirm="Start the session and the game clock?"
          >
            ▶ Start session
          </button>
          <button
            :if={@snap.status == :live}
            phx-click="pause"
            class="btn btn-sm btn-warning btn-soft"
          >
            ⏸ Pause
          </button>
          <button :if={@snap.status == :paused} phx-click="resume" class="btn btn-sm btn-primary">
            ▶ Resume
          </button>
          <button
            :if={@snap.status in [:live, :paused]}
            phx-click="end_session"
            class="btn btn-sm btn-error btn-soft"
            data-confirm="End the session? Decisions close; you'll pick an ending."
          >
            ⏹ End
          </button>
          <.link navigate={~p"/scenarios/#{@scenario.id}/sessions"} class="btn btn-sm btn-ghost">
            ← Sessions
          </.link>
        </:actions>
      </.header>

      <%!-- Live board --%>
      <div class="mt-6 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Group</th>
              <th :for={vd <- value_dims(@snap)} class="text-right">
                {I18n.t!(vd.name, @locale, default: vd.key)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={g <- groups(@snap)}>
              <td class="font-medium whitespace-nowrap">
                {I18n.t!(g.name, @locale, default: g.handle)}
              </td>
              <td
                :for={vd <- value_dims(@snap)}
                class={["text-right tabular-nums", cell_class(@snap.sim, vd, g.id)]}
              >
                {fmt_num(Sim.get(@snap.sim, vd.id, g.id))}
              </td>
            </tr>
            <tr class="border-t-2 border-base-300 font-semibold">
              <td>Global</td>
              <td :for={vd <- value_dims(@snap)} class="text-right tabular-nums">
                {fmt_num(@snap.globals[vd.id])}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Timeline --%>
      <div class="mt-8 space-y-6">
        <section
          :for={element <- elements(@snap)}
          class={[
            "rounded-box border border-base-300 p-4 space-y-3",
            element.id in @snap.triggered && "border-primary/40"
          ]}
        >
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-lg font-semibold">
              <span class="opacity-50">{element.position}.</span>
              {I18n.t!(element.title, @locale, default: element.handle)}
            </h3>
            <span class="badge badge-sm">{element.kind}</span>
            <span :if={element.id in @snap.triggered} class="badge badge-sm badge-primary badge-soft">
              triggered
            </span>
            <span :if={deadline_left(@snap, element)} class={deadline_class(@snap, element)}>
              ⏱ {fmt_deadline_left(deadline_left(@snap, element))}
            </span>
            <button
              :if={element.id not in @snap.triggered}
              phx-click="trigger"
              phx-value-id={element.id}
              disabled={@snap.status not in [:live, :paused]}
              class="btn btn-sm btn-primary ml-auto"
            >
              Trigger
            </button>
          </div>

          <p :if={notes = notes(element, @locale)} class="rounded bg-base-200 p-2 text-xs italic">
            🎭 {notes}
          </p>

          <%!-- Decision entry, once triggered --%>
          <div :if={element.id in @snap.triggered}>
            <%!-- Event: one decision per group --%>
            <div :if={element.kind == :event} class="space-y-2">
              <div :for={g <- groups(@snap)} class="flex flex-wrap items-center gap-2">
                <span class="w-40 truncate text-sm font-medium">
                  {I18n.t!(g.name, @locale, default: g.handle)}
                </span>
                <button
                  :for={o <- options_for_group(@snap, element.id, g.id)}
                  phx-click="choose"
                  phx-value-element={element.id}
                  phx-value-group={g.id}
                  phx-value-option={o.id}
                  disabled={@snap.status not in [:live, :paused]}
                  class={[
                    "btn btn-xs normal-case",
                    decided?(@snap, element.id, g.id, o.id) && "btn-primary"
                  ]}
                >
                  {o.handle}
                  <span :if={o.is_default} class="badge badge-xs badge-ghost">default</span>
                  <span :if={o.condition} class="badge badge-xs badge-warning font-mono">
                    {o.condition}
                  </span>
                </button>
              </div>
            </div>

            <%!-- Election: hand-count tally + winner --%>
            <form
              :if={element.kind == :election}
              phx-submit="resolve_election"
              class="space-y-2"
            >
              <input type="hidden" name="element" value={element.id} />
              <div
                :for={o <- options_for_element(@snap, element.id)}
                class="flex flex-wrap items-center gap-2"
              >
                <label class="flex items-center gap-2">
                  <input
                    type="radio"
                    name="winner"
                    value={o.id}
                    checked={decided?(@snap, element.id, :winner, o.id)}
                    class="radio radio-sm"
                  />
                  <span class={[
                    "text-sm",
                    decided?(@snap, element.id, :winner, o.id) && "font-bold text-primary"
                  ]}>
                    {o.handle}
                  </span>
                  <span :if={o.condition} class="badge badge-xs badge-warning font-mono">
                    {o.condition}
                  </span>
                </label>
                <input
                  type="number"
                  name={"tally[#{o.id}]"}
                  min="0"
                  placeholder="votes"
                  class="input input-bordered input-xs w-20"
                />
              </div>
              <button
                type="submit"
                disabled={@snap.status not in [:live, :paused]}
                class="btn btn-sm btn-primary"
              >
                Declare result
              </button>
            </form>

            <%!-- Sidequest: adjudicate --%>
            <div :if={element.kind == :sidequest} class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-medium">Adjudicate:</span>
              <button
                :for={o <- options_for_element(@snap, element.id)}
                phx-click="adjudicate"
                phx-value-element={element.id}
                phx-value-option={o.id}
                disabled={@snap.status not in [:live, :paused]}
                class={[
                  "btn btn-xs normal-case",
                  decided?(@snap, element.id, :outcome, o.id) && "btn-primary"
                ]}
              >
                {o.outcome} — {o.handle}
              </button>
            </div>
          </div>
        </section>
      </div>

      <%!-- Endings (after the end) --%>
      <section :if={@snap.status == :ended} class="mt-10 space-y-3">
        <h3 class="text-lg font-semibold">Choose the ending</h3>
        <p class="text-xs opacity-60">
          Recommendations from the final board — you have the last word.
        </p>
        <ul class="space-y-1">
          <li
            :for={ending <- endings(@snap)}
            class={[
              "flex flex-wrap items-center gap-2 rounded bg-base-200 px-3 py-2",
              @snap.ending_id == ending.id && "ring-2 ring-primary"
            ]}
          >
            <span class="font-medium">{ending.handle}</span>
            <span class="text-sm opacity-70">
              — {I18n.t!(ending.title, @locale, default: "—")}
            </span>
            <span :if={ending.condition} class="badge badge-xs font-mono">{ending.condition}</span>
            <span
              :if={recommended?(ending, @snap)}
              class="badge badge-sm badge-success"
            >
              recommended
            </span>
            <button
              phx-click="select_ending"
              phx-value-id={ending.id}
              class={["btn btn-xs ml-auto", (@snap.ending_id == ending.id && "btn-primary") || ""]}
            >
              {if @snap.ending_id == ending.id, do: "Selected", else: "Select"}
            </button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    user = socket.assigns.current_scope.user
    session = Play.get_session!(session_id)

    case Authoring.get_scenario_for_user(session.scenario_id, user) do
      {scenario, role} when role in [:owner, :author] ->
        if connected?(socket) do
          Play.subscribe(session.id)
          :timer.send_interval(1000, :tick)
        end

        {:ok,
         socket
         |> assign(
           session: session,
           scenario: scenario,
           locale: scenario.source_locale,
           page_title: "Console — #{session.label}",
           snap: Play.snapshot(session.id)
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You cannot run sessions for this scenario.")
         |> push_navigate(to: ~p"/scenarios")}
    end
  end

  # ── Commands ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("start", _params, socket), do: run(socket, &Play.start_session/1)
  def handle_event("pause", _params, socket), do: run(socket, &Play.pause_session/1)
  def handle_event("resume", _params, socket), do: run(socket, &Play.resume_session/1)
  def handle_event("end_session", _params, socket), do: run(socket, &Play.end_session/1)

  def handle_event("trigger", %{"id" => element_id}, socket),
    do: run(socket, &Play.trigger_element(&1, element_id))

  def handle_event(
        "choose",
        %{"element" => element_id, "group" => group_id, "option" => option_id},
        socket
      ),
      do: run(socket, &Play.choose_option(&1, element_id, group_id, option_id))

  def handle_event("resolve_election", %{"element" => element_id} = params, socket) do
    case params["winner"] do
      winner when is_binary(winner) and winner != "" ->
        tally = parse_tally(params["tally"] || %{})
        run(socket, &Play.resolve_election(&1, element_id, winner, tally))

      _ ->
        {:noreply, put_flash(socket, :error, "Pick the winning option first.")}
    end
  end

  def handle_event("adjudicate", %{"element" => element_id, "option" => option_id}, socket),
    do: run(socket, &Play.adjudicate_sidequest(&1, element_id, option_id))

  def handle_event("select_ending", %{"id" => ending_id}, socket),
    do: run(socket, &Play.select_ending(&1, ending_id))

  defp run(socket, command) do
    case command.(socket.assigns.session.id) do
      {:ok, snapshot} ->
        {:noreply, assign(socket, :snap, snapshot)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Rejected: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:session_updated, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(:tick, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    assign(socket, :snap, Play.snapshot(socket.assigns.session.id))
  end

  defp parse_tally(tally) when is_map(tally) do
    for {option_id, raw} <- tally, raw not in [nil, ""], into: %{} do
      case Integer.parse(to_string(raw)) do
        {count, _} -> {option_id, count}
        :error -> {option_id, 0}
      end
    end
  end

  # ── Snapshot accessors ────────────────────────────────────────────────

  defp value_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_group))

  defp groups(snap), do: Enum.map(snap.definition.group_ids, &snap.definition.groups[&1])

  defp elements(snap), do: Enum.map(snap.definition.element_order, &snap.definition.elements[&1])

  defp endings(snap), do: snap.definition.endings

  defp options_for_element(snap, element_id),
    do: snap.definition.options_by_element[element_id] || []

  defp options_for_group(snap, element_id, group_id),
    do: Enum.filter(options_for_element(snap, element_id), &(&1.group_id == group_id))

  defp decided?(snap, element_id, slot, option_id),
    do: get_in(snap.decisions, [element_id, slot]) == option_id

  defp notes(element, locale), do: I18n.t(element.director_notes, locale)

  # ── Deadlines ─────────────────────────────────────────────────────────

  defp deadline_left(snap, %{deadline_seconds: seconds} = element) when is_integer(seconds) do
    case snap.triggered_at[element.id] do
      nil -> nil
      triggered_at -> triggered_at + seconds * 1000 - snap.game_time_ms
    end
  end

  defp deadline_left(_snap, _element), do: nil

  defp deadline_class(snap, element) do
    left = deadline_left(snap, element)

    cond do
      left <= 0 -> "badge badge-sm badge-error"
      left < 60_000 -> "badge badge-sm badge-warning"
      true -> "badge badge-sm badge-ghost"
    end
  end

  defp fmt_deadline_left(ms) when ms <= 0, do: "lapsed"
  defp fmt_deadline_left(ms), do: fmt_clock(ms)

  # ── Endings ───────────────────────────────────────────────────────────

  defp recommended?(%{condition: nil}, _snap), do: false

  defp recommended?(%{condition: condition}, snap) do
    context = %{
      global:
        Map.new(
          for vd <- snap.definition.value_dimensions, is_number(snap.globals[vd.id]) do
            {vd.key, snap.globals[vd.id]}
          end
        )
    }

    match?({:ok, true}, Condition.evaluate(condition, context))
  end

  # ── Formatting ────────────────────────────────────────────────────────

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:live), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:ended), do: "badge-neutral"

  defp fmt_clock(ms) do
    total_seconds = div(max(ms, 0), 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, seconds]) |> to_string()
  end

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

  defp fmt_num(n) when is_float(n) do
    rounded = Float.round(n, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end

  defp fmt_num(n), do: to_string(n)
end
