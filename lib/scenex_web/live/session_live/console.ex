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
                {fmt_num(Sim.get(@snap.sim, vd.id, g.id))}<.value_delta change={
                  Play.recent_delta(@snap, vd.id, g.id)
                } />
              </td>
            </tr>
            <tr class="border-t-2 border-base-300 font-semibold">
              <td>Global</td>
              <td :for={vd <- value_dims(@snap)} class="text-right tabular-nums">
                {fmt_num(@snap.globals[vd.id])}<.value_delta change={Play.recent_delta(@snap, vd.id)} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Well-being: hand-count tallies for per-participant values --%>
      <section
        :for={vd <- participant_dims(@snap)}
        class="mt-8 rounded-box border border-base-300 p-4 space-y-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-lg font-semibold">{I18n.t!(vd.name, @locale, default: vd.key)}</h3>
          <span class="badge badge-sm badge-ghost">hand count</span>
          <span
            :if={avg = @snap.globals[vd.id]}
            class="ml-auto text-xl font-bold tabular-nums"
            title="Latest tally average"
          >
            {tally_face(avg)} {fmt_num(avg)}<.value_delta change={Play.recent_delta(@snap, vd.id)} />
          </span>
        </div>

        <form
          phx-submit="record_tally"
          phx-change="tally_change"
          class="flex flex-wrap items-end gap-3"
        >
          <input type="hidden" name="value" value={vd.id} />
          <label :for={{score, face, label} <- tally_scale()} class="flex flex-col gap-1 text-xs">
            <span class="whitespace-nowrap">{face} {label} ({score})</span>
            <input
              type="number"
              name={"counts[#{score}]"}
              value={get_in(@tally_inputs, [vd.id, to_string(score)])}
              min="0"
              placeholder="0"
              class="input input-bordered w-24 text-right"
            />
          </label>
          <button
            type="submit"
            disabled={@snap.status not in [:live, :paused]}
            class="btn btn-sm btn-primary"
          >
            Record tally
          </button>
        </form>

        <div :if={tally_history(@snap, vd.id) != []} class="overflow-x-auto">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>Time</th>
                <th :for={{_score, face, _label} <- tally_scale()} class="text-right">{face}</th>
                <th class="text-right">Average</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- Enum.reverse(tally_history(@snap, vd.id))}>
                <td class="font-mono tabular-nums">{fmt_clock(entry.game_time_ms)}</td>
                <td :for={{score, _face, _label} <- tally_scale()} class="text-right tabular-nums">
                  {entry.counts[score] || 0}
                </td>
                <td class="text-right font-semibold tabular-nums">
                  {fmt_num(Sim.tally_mean(entry.counts))}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

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
            <span
              :if={Play.element_decided?(@snap, element)}
              class="badge badge-sm badge-success badge-soft"
            >
              decided
            </span>
            <span
              :if={deadline_left(@snap, element) && !Play.element_decided?(@snap, element)}
              class={deadline_class(@snap, element)}
            >
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
              phx-change="election_change"
              class="space-y-2"
            >
              <input type="hidden" name="element" value={element.id} />
              <div
                :for={o <- options_for_element(@snap, element.id)}
                class="grid max-w-xl grid-cols-[minmax(0,1fr)_6rem] items-center gap-2"
              >
                <label class="flex cursor-pointer items-center gap-2">
                  <input
                    type="radio"
                    name="winner"
                    value={o.id}
                    checked={winner_choice(@election_inputs, @snap, element.id) == o.id}
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
                  value={get_in(@election_inputs, [element.id, "tally", o.id])}
                  min="0"
                  placeholder="votes"
                  class="input input-bordered input-sm w-24 text-right"
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

      <%!-- Access: QR tokens for group tables and the projected display --%>
      <section class="mt-10 space-y-3">
        <h3 class="text-lg font-semibold">Access &amp; QR</h3>
        <p class="text-xs opacity-60">
          A group token lets one table enter its own decisions; the display token is the
          read-only board for the wall. No accounts — the code is the key.
        </p>

        <div class="flex flex-wrap gap-2">
          <button
            :for={g <- groups(@snap)}
            :if={not has_token?(@tokens, g.id)}
            phx-click="gen_group_token"
            phx-value-group={g.id}
            class="btn btn-xs"
          >
            + Code: {I18n.t!(g.name, @locale, default: g.handle)}
          </button>
          <button
            :if={not has_display_token?(@tokens)}
            phx-click="gen_display_token"
            class="btn btn-xs"
          >
            + Code: projected display
          </button>
        </div>

        <div class="flex flex-wrap gap-4">
          <div :for={token <- @tokens} class="card bg-base-200">
            <div class="card-body items-center p-4">
              <span class="font-medium">
                {token_label(token, @locale)}
              </span>
              {Phoenix.HTML.raw(qr_svg(token_url(token)))}
              <a href={token_url(token)} target="_blank" class="link max-w-48 truncate text-xs">
                {token_url(token)}
              </a>
              <button
                phx-click="delete_token"
                phx-value-id={token.id}
                data-confirm="Revoke this code? The QR stops working immediately."
                class="btn btn-xs btn-error btn-soft"
              >
                Revoke
              </button>
            </div>
          </div>
        </div>
      </section>

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
        if Play.gm?(session, user, role) do
          mount_console(socket, session, scenario)
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             "This session is run by another GM — only its creator or the scenario owner can control it."
           )
           |> push_navigate(to: ~p"/scenarios/#{session.scenario_id}/sessions")}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You cannot run sessions for this scenario.")
         |> push_navigate(to: ~p"/scenarios")}
    end
  end

  defp mount_console(socket, session, scenario) do
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
       snap: Play.snapshot(session.id),
       tokens: Play.list_tokens(session),
       tally_inputs: %{},
       election_inputs: %{}
     )}
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

        run(
          socket,
          &Play.resolve_election(&1, element_id, winner, tally),
          fn socket ->
            socket
            |> clear_input(:election_inputs, element_id)
            |> put_flash(:info, "Result declared. Declaring again overwrites it.")
          end
        )

      _ ->
        {:noreply, put_flash(socket, :error, "Pick the winning option first.")}
    end
  end

  # Keep in-progress form input in assigns: the console re-renders every tick
  # (game clock), and uncontrolled inputs would be reset to empty each second.
  def handle_event("election_change", %{"element" => element_id} = params, socket) do
    inputs =
      Map.put(socket.assigns.election_inputs, element_id, Map.take(params, ["winner", "tally"]))

    {:noreply, assign(socket, :election_inputs, inputs)}
  end

  def handle_event("tally_change", %{"value" => value_id} = params, socket) do
    inputs = Map.put(socket.assigns.tally_inputs, value_id, params["counts"] || %{})
    {:noreply, assign(socket, :tally_inputs, inputs)}
  end

  def handle_event("adjudicate", %{"element" => element_id, "option" => option_id}, socket),
    do: run(socket, &Play.adjudicate_sidequest(&1, element_id, option_id))

  def handle_event("record_tally", %{"value" => value_id} = params, socket) do
    counts = parse_tally(params["counts"] || %{})

    if counts == %{} or counts |> Map.values() |> Enum.sum() == 0 do
      {:noreply, put_flash(socket, :error, "Count at least one participant first.")}
    else
      run(
        socket,
        &Play.record_tally(&1, value_id, counts),
        &clear_input(&1, :tally_inputs, value_id)
      )
    end
  end

  def handle_event("select_ending", %{"id" => ending_id}, socket),
    do: run(socket, &Play.select_ending(&1, ending_id))

  def handle_event("gen_group_token", %{"group" => group_id}, socket) do
    group = socket.assigns.snap.definition.groups[group_id]
    {:ok, _token} = Play.create_group_token(socket.assigns.session, group)
    {:noreply, reload_tokens(socket)}
  end

  def handle_event("gen_display_token", _params, socket) do
    {:ok, _token} = Play.create_display_token(socket.assigns.session)
    {:noreply, reload_tokens(socket)}
  end

  def handle_event("delete_token", %{"id" => id}, socket) do
    socket.assigns.tokens
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> :ok
      token -> Play.delete_token(token)
    end

    {:noreply, reload_tokens(socket)}
  end

  defp reload_tokens(socket),
    do: assign(socket, :tokens, Play.list_tokens(socket.assigns.session))

  defp run(socket, command, on_success \\ & &1) do
    case command.(socket.assigns.session.id) do
      {:ok, snapshot} ->
        {:noreply, socket |> assign(:snap, snapshot) |> on_success.()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Rejected: #{inspect(reason)}")}
    end
  end

  # Drop one form's held input (after its command succeeded).
  defp clear_input(socket, key, id),
    do: assign(socket, key, Map.delete(socket.assigns[key], id))

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

  defp participant_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_participant))

  defp tally_history(snap, value_id), do: snap.tallies[value_id] || []

  # The fixed 4-step smiley-coin scale (see the well-being design concept).
  defp tally_scale do
    [
      {4, "😀", "Very happy"},
      {3, "🙂", "Happy"},
      {2, "😐", "Okay"},
      {1, "🙁", "Not happy"}
    ]
  end

  defp tally_face(avg) when avg >= 3.5, do: "😀"
  defp tally_face(avg) when avg >= 2.5, do: "🙂"
  defp tally_face(avg) when avg >= 1.5, do: "😐"
  defp tally_face(_avg), do: "🙁"

  defp groups(snap), do: Enum.map(snap.definition.group_ids, &snap.definition.groups[&1])

  defp elements(snap), do: Enum.map(snap.definition.element_order, &snap.definition.elements[&1])

  defp endings(snap), do: snap.definition.endings

  defp options_for_element(snap, element_id),
    do: snap.definition.options_by_element[element_id] || []

  defp options_for_group(snap, element_id, group_id),
    do: Enum.filter(options_for_element(snap, element_id), &(&1.group_id == group_id))

  defp decided?(snap, element_id, slot, option_id),
    do: get_in(snap.decisions, [element_id, slot]) == option_id

  # The radio reflects what the GM is picking right now, falling back to the
  # recorded winner (so a declared result stays visible).
  defp winner_choice(inputs, snap, element_id) do
    get_in(inputs, [element_id, "winner"]) || get_in(snap.decisions, [element_id, :winner])
  end

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

  # ── Tokens & QR ───────────────────────────────────────────────────────

  defp has_token?(tokens, group_id),
    do: Enum.any?(tokens, &(&1.kind == :group and &1.group_id == group_id))

  defp has_display_token?(tokens), do: Enum.any?(tokens, &(&1.kind == :display))

  defp token_label(%{kind: :display}, _locale), do: "Projected display"

  defp token_label(%{kind: :group, group: group}, locale),
    do: I18n.t!(group.name, locale, default: group.handle)

  defp token_url(%{kind: :display, token: token}), do: url(~p"/display/#{token}")
  defp token_url(%{token: token}), do: url(~p"/play/#{token}")

  defp qr_svg(url) do
    url |> EQRCode.encode() |> EQRCode.svg(width: 140)
  end

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
