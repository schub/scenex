defmodule ScenexWeb.PlayLive.Display do
  @moduledoc """
  The projected display — read-only, opened via a display token, no login.

  Meant for the wall: session name, game clock, the derived scoreboard
  (global values, well-being, and the democracy score — a group's own
  standing belongs on its own screen, not the shared one), and the current
  beat (the latest triggered element's narrative, an election result, and —
  once the GM has chosen — the ending). Full-height, no scroll: the GM's
  four board-section toggles decide what's on screen, and whatever remains
  splits the available height evenly. Updates live via PubSub; keeps
  working after the session ends (the finale stays on the wall).
  """
  use ScenexWeb, :live_view

  alias Scenex.Play
  alias Scenex.Engine.Scale
  alias Scenex.I18n

  # Well-being reads as an emoji, not a label — same 4 equal bands as the
  # gauge's tick position, just a different readout. Democracy score keeps
  # a text label, best to worst — see Scenex.Engine.Scale.
  @wellbeing_emojis ["😀", "🙂", "😐", "🙁"]
  @wellbeing_min 1.0
  @wellbeing_max 4.0
  @democracy_labels ["In Bloom", "Resilient", "Fragile", "Critical", "Breakdown"]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.play flash={@flash}>
      <div class="flex h-screen flex-col gap-6 overflow-hidden p-6">
        <div class="relative shrink-0">
          <h1 class="text-center text-4xl font-bold">{@session_label}</h1>
          <div class="absolute top-0 right-0 flex items-center gap-3">
            <span class={["badge badge-lg", status_badge(@snap.status)]}>
              {status_label(@snap.status)}
            </span>
            <span class="font-mono text-3xl tabular-nums">{fmt_clock(@snap.game_time_ms)}</span>
          </div>
        </div>

        <%!-- The current beat: narrative, election result, and the finale
        once chosen — one GM toggle covers all three. --%>
        <div :if={@snap.board_sections.current_beat} class="shrink-0 space-y-4">
          <section
            :if={ending = chosen_ending(@snap)}
            class="rounded-box bg-base-200 p-6 space-y-3"
          >
            <h2 class="text-3xl font-bold">
              {I18n.t!(ending.title, @locale, default: ending.handle)}
            </h2>
            <.markdown text={I18n.t(ending.narrative, @locale)} class="text-xl" />
          </section>

          <section
            :for={element <- List.wrap(current_element(@snap))}
            :if={chosen_ending(@snap) == nil}
            class="rounded-box bg-base-200 p-6 space-y-3"
          >
            <h2 class="text-3xl font-bold">
              {I18n.t!(element.title, @locale, default: element.handle)}
              <span
                :if={Play.element_decided?(@snap, element)}
                class="badge badge-lg badge-success ml-2 align-middle"
              >
                ✓ {gettext("decided")}
              </span>
            </h2>

            <%!-- The deadline countdown: a draining progress bar, full
            width, with the time remaining alongside it. --%>
            <% deadline = deadline_status(@snap, element) %>
            <div
              :if={not Play.element_decided?(@snap, element) and deadline}
              class="space-y-1"
            >
              <div class="text-right font-mono text-lg tabular-nums opacity-70">
                {fmt_clock(deadline.left_ms)}
              </div>
              <div class="h-4 w-full overflow-hidden rounded-full bg-base-300">
                <div
                  class={["h-full rounded-full transition-all", deadline_bar_color(deadline.pct)]}
                  style={"width: #{deadline.pct}%"}
                />
              </div>
            </div>

            <%!-- Election result, once declared --%>
            <div
              :if={winner = declared_winner(@snap, element)}
              class="rounded-box bg-base-100 p-4 space-y-2"
            >
              <div class="flex flex-wrap items-baseline gap-3">
                <span class="badge badge-lg badge-success">{gettext("Result")}</span>
                <span class="text-2xl font-bold">
                  {I18n.t!(winner.text, @locale, default: winner.handle)}
                </span>
              </div>
              <div
                :if={vote_lines(@snap, element) != []}
                class="flex flex-wrap gap-x-6 gap-y-1 text-lg opacity-80"
              >
                <span :for={{option, count} <- vote_lines(@snap, element)}>
                  {I18n.t!(option.text, @locale, default: option.handle)}:
                  <span class="font-semibold tabular-nums">{count}</span>
                </span>
              </div>
            </div>
          </section>
        </div>

        <%!-- The scoreboard proper: whatever sections are on splits the
        remaining height evenly, full width, no scrolling. --%>
        <div class="flex min-h-0 flex-1 flex-col gap-4">
          <div
            :if={@snap.board_sections.globals and value_dims(@snap) != []}
            class="flex min-h-0 flex-1 flex-wrap items-center justify-center gap-10"
          >
            <div :for={vd <- value_dims(@snap)} class="text-center">
              <div class="text-4xl font-bold">{I18n.t!(vd.name, @locale, default: vd.key)}</div>
              <.value_bar
                value={@snap.globals[vd.id]}
                min={vd.min}
                max={vd.max}
                change={Play.recent_delta(@snap, vd.id)}
                show_numbers={@snap.show_numbers}
                class="mt-2"
              />
            </div>
          </div>

          <div
            :for={vd <- wellbeing_dims(@snap)}
            :if={@snap.board_sections.wellbeing}
            class="flex min-h-0 flex-1 items-center justify-center gap-10 px-16"
          >
            <div class="w-64 shrink-0 text-right text-2xl font-semibold opacity-70">
              {I18n.t!(vd.name, @locale, default: vd.key)}
            </div>
            <.scale_gauge
              value={@snap.globals[vd.id]}
              min={wellbeing_min()}
              max={wellbeing_max()}
              readout={wellbeing_readout(@snap, vd)}
            />
          </div>

          <div
            :if={@snap.board_sections.democracy and democracy_score(@snap) != nil}
            class="flex min-h-0 flex-1 items-center justify-center gap-10 px-16"
          >
            <div class="w-64 shrink-0 text-right text-2xl font-semibold opacity-70">
              {gettext("Democracy Score")}
            </div>
            <.scale_gauge
              value={democracy_score(@snap)}
              min={@snap.definition.democracy_min}
              max={@snap.definition.democracy_max}
              readout={democracy_readout(@snap)}
            />
          </div>
        </div>

        <p :if={@snap.status == :draft} class="shrink-0 text-center text-2xl opacity-60">
          {gettext("The show will begin shortly.")}
        </p>
      </div>
    </Layouts.play>
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
        locale = token.session.locale || scenario.source_locale
        Gettext.put_locale(ScenexWeb.Gettext, locale)

        {:ok,
         socket
         |> assign(
           session_id: token.session_id,
           session_label: token.session.label,
           locale: locale,
           page_title: token.session.label,
           snap: Play.snapshot(token.session_id)
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This code is not valid (anymore)."))
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

  # Per-participant values with at least one recorded tally — nothing to
  # gauge before the first hand count comes in.
  defp wellbeing_dims(snap) do
    Enum.filter(
      snap.definition.value_dimensions,
      &(&1.input_scope == :per_participant and is_number(snap.globals[&1.id]))
    )
  end

  defp wellbeing_min, do: @wellbeing_min
  defp wellbeing_max, do: @wellbeing_max

  defp wellbeing_readout(snap, vd) do
    case snap.globals[vd.id] do
      value when is_number(value) ->
        Enum.at(
          @wellbeing_emojis,
          Scale.index(value, @wellbeing_min, @wellbeing_max, length(@wellbeing_emojis))
        )

      _ ->
        "—"
    end
  end

  defp democracy_readout(snap) do
    case democracy_score(snap) do
      score when is_number(score) ->
        Scale.label(
          score,
          snap.definition.democracy_min,
          snap.definition.democracy_max,
          @democracy_labels
        )

      _ ->
        "—"
    end
  end

  # The number, or nil if unconfigured or unavailable — the gauge already
  # reads nil as "—", and the section hides itself when there's nothing to
  # show (no per-group values defined yet).
  defp democracy_score(snap) do
    case Play.democracy_score(snap) do
      {:ok, score} -> score
      _ -> nil
    end
  end

  # The latest triggered element that isn't closed yet. Once the GM closes
  # it, it drops off the wall entirely — closing means "we're done with
  # this," not just "stop the countdown."
  defp current_element(snap) do
    case Enum.find(Enum.reverse(snap.triggered), &(&1 not in snap.closed)) do
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

  # Time left and share of the deadline still remaining (0..100) — nil once
  # it lapses (the countdown simply disappears rather than sitting at zero)
  # or for elements with no deadline configured at all.
  defp deadline_status(snap, %{deadline_seconds: seconds} = element)
       when is_integer(seconds) and seconds > 0 do
    case snap.triggered_at[element.id] do
      nil ->
        nil

      triggered_at ->
        left = triggered_at + seconds * 1000 - snap.game_time_ms
        if left > 0, do: %{left_ms: left, pct: (left / (seconds * 1000) * 100) |> min(100.0)}
    end
  end

  defp deadline_status(_snap, _element), do: nil

  defp deadline_bar_color(pct) when pct <= 20, do: "bg-error"
  defp deadline_bar_color(pct) when pct <= 50, do: "bg-warning"
  defp deadline_bar_color(_pct), do: "bg-primary"

  # ── Formatting ────────────────────────────────────────────────────────

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:live), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:ended), do: "badge-neutral"

  defp status_label(:draft), do: gettext("draft")
  defp status_label(:live), do: gettext("live")
  defp status_label(:paused), do: gettext("paused")
  defp status_label(:ended), do: gettext("ended")

  defp fmt_clock(ms) do
    total_seconds = div(max(ms, 0), 1000)

    :io_lib.format("~2..0B:~2..0B", [div(total_seconds, 60), rem(total_seconds, 60)])
    |> to_string()
  end
end
