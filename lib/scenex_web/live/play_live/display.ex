defmodule ScenexWeb.PlayLive.Display do
  @moduledoc """
  The projected display — read-only, opened via a display token, no login.

  Meant for the wall: the board (groups × values + globals), the game clock,
  the latest triggered element's title and narrative, and — once the GM has
  chosen — the ending. Updates live via PubSub; keeps working after the
  session ends (the finale stays on the wall).
  """
  use ScenexWeb, :live_view

  alias Scenex.Play
  alias Scenex.Engine.Sim
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl space-y-8 py-8">
        <div class="flex items-baseline justify-between">
          <h1 class="text-3xl font-bold">{@session_label}</h1>
          <div class="flex items-center gap-3">
            <span class={["badge", status_badge(@snap.status)]}>{@snap.status}</span>
            <span class="font-mono text-2xl tabular-nums">{fmt_clock(@snap.game_time_ms)}</span>
          </div>
        </div>

        <%!-- The board --%>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th class="text-base">Group</th>
                <th :for={vd <- value_dims(@snap)} class="text-right text-base">
                  {I18n.t!(vd.name, @locale, default: vd.key)}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={g <- groups(@snap)}>
                <td class="text-lg font-medium">{I18n.t!(g.name, @locale, default: g.handle)}</td>
                <td
                  :for={vd <- value_dims(@snap)}
                  class={["text-right text-lg tabular-nums", cell_class(@snap.sim, vd, g.id)]}
                >
                  {fmt_num(Sim.get(@snap.sim, vd.id, g.id))}
                </td>
              </tr>
              <tr class="border-t-2 border-base-300 text-xl font-bold">
                <td>Global</td>
                <td :for={vd <- value_dims(@snap)} class="text-right tabular-nums">
                  {fmt_num(@snap.globals[vd.id])}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Well-being: the latest hand-count tally per participant value --%>
        <section :if={tallied_dims(@snap) != []} class="flex flex-wrap justify-center gap-6">
          <div
            :for={vd <- tallied_dims(@snap)}
            class="rounded-box bg-base-200 px-6 py-4 text-center"
          >
            <div class="text-sm opacity-70">{I18n.t!(vd.name, @locale, default: vd.key)}</div>
            <div class="flex items-baseline justify-center gap-3">
              <span class="text-3xl">{tally_face(@snap.globals[vd.id])}</span>
              <span class="text-3xl font-bold tabular-nums">{fmt_num(@snap.globals[vd.id])}</span>
            </div>
          </div>
        </section>

        <%!-- The finale, once chosen --%>
        <section :if={ending = chosen_ending(@snap)} class="rounded-box bg-base-200 p-6 space-y-3">
          <h2 class="text-2xl font-bold">{I18n.t!(ending.title, @locale, default: ending.handle)}</h2>
          <p class="whitespace-pre-line text-lg">{I18n.t(ending.narrative, @locale)}</p>
        </section>

        <%!-- The current beat --%>
        <section
          :for={element <- List.wrap(current_element(@snap))}
          :if={chosen_ending(@snap) == nil}
          class="rounded-box bg-base-200 p-6 space-y-3"
        >
          <h2 class="text-2xl font-bold">
            {I18n.t!(element.title, @locale, default: element.handle)}
            <span
              :if={Play.element_decided?(@snap, element)}
              class="badge badge-lg badge-success ml-2 align-middle"
            >
              ✓ decided
            </span>
            <span
              :if={!Play.element_decided?(@snap, element) && deadline_left(@snap, element)}
              class="badge badge-lg ml-2 align-middle"
            >
              ⏱ {fmt_deadline_left(deadline_left(@snap, element))}
            </span>
          </h2>
          <p class="whitespace-pre-line text-lg">{I18n.t(element.narrative, @locale)}</p>

          <%!-- Election result, once declared --%>
          <div
            :if={winner = declared_winner(@snap, element)}
            class="rounded-box bg-base-100 p-4 space-y-2"
          >
            <div class="flex flex-wrap items-baseline gap-3">
              <span class="badge badge-success">Result</span>
              <span class="text-xl font-bold">
                {I18n.t!(winner.text, @locale, default: winner.handle)}
              </span>
            </div>
            <div
              :if={vote_lines(@snap, element) != []}
              class="flex flex-wrap gap-x-6 gap-y-1 text-base opacity-80"
            >
              <span :for={{option, count} <- vote_lines(@snap, element)}>
                {I18n.t!(option.text, @locale, default: option.handle)}:
                <span class="font-semibold tabular-nums">{count}</span>
              </span>
            </div>
          </div>
        </section>

        <p :if={@snap.status == :draft} class="text-center text-xl opacity-60">
          The show will begin shortly.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token_string}, _session, socket) do
    case Play.fetch_token(token_string) do
      {:ok, %{kind: :display} = token} ->
        if connected?(socket) do
          Play.subscribe(token.session_id)
          :timer.send_interval(1000, :tick)
        end

        scenario = Scenex.Authoring.get_scenario!(token.session.scenario_id)

        {:ok,
         socket
         |> assign(
           session_id: token.session_id,
           session_label: token.session.label,
           locale: scenario.source_locale,
           page_title: token.session.label,
           snap: Play.snapshot(token.session_id)
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "This code is not valid (anymore).")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:session_updated, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(:tick, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket), do: assign(socket, :snap, Play.snapshot(socket.assigns.session_id))

  # ── Snapshot accessors ────────────────────────────────────────────────

  defp value_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_group))

  # Per-participant values with at least one recorded tally.
  defp tallied_dims(snap) do
    Enum.filter(
      snap.definition.value_dimensions,
      &(&1.input_scope == :per_participant and is_number(snap.globals[&1.id]))
    )
  end

  defp tally_face(avg) when avg >= 3.5, do: "😀"
  defp tally_face(avg) when avg >= 2.5, do: "🙂"
  defp tally_face(avg) when avg >= 1.5, do: "😐"
  defp tally_face(_avg), do: "🙁"

  defp groups(snap), do: Enum.map(snap.definition.group_ids, &snap.definition.groups[&1])

  defp current_element(snap) do
    case List.last(snap.triggered) do
      nil -> nil
      eid -> snap.definition.elements[eid]
    end
  end

  defp chosen_ending(%{ending_id: nil}), do: nil

  defp chosen_ending(snap),
    do: Enum.find(snap.definition.endings, &(&1.id == snap.ending_id))

  defp declared_winner(snap, %{kind: :election} = element) do
    case get_in(snap.decisions, [element.id, :winner]) do
      nil -> nil
      option_id -> snap.definition.options[option_id]
    end
  end

  defp declared_winner(_snap, _element), do: nil

  # The declared hand count, in ballot order; options without a count are
  # omitted (a lapsed-deadline default winner has no tally).
  defp vote_lines(snap, element) do
    tally = snap.vote_tallies[element.id] || %{}

    for option <- snap.definition.options_by_element[element.id] || [],
        count = tally[option.id],
        do: {option, count}
  end

  defp deadline_left(snap, %{deadline_seconds: seconds} = element) when is_integer(seconds) do
    case snap.triggered_at[element.id] do
      nil -> nil
      triggered_at -> triggered_at + seconds * 1000 - snap.game_time_ms
    end
  end

  defp deadline_left(_snap, _element), do: nil

  defp fmt_deadline_left(ms) when ms <= 0, do: "—"
  defp fmt_deadline_left(ms), do: fmt_clock(ms)

  # ── Formatting ────────────────────────────────────────────────────────

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:live), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:ended), do: "badge-neutral"

  defp fmt_clock(ms) do
    total_seconds = div(max(ms, 0), 1000)

    :io_lib.format("~2..0B:~2..0B", [div(total_seconds, 60), rem(total_seconds, 60)])
    |> to_string()
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
