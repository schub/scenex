defmodule ScenexWeb.SessionLive.Console do
  @moduledoc """
  The GM console — running one live session (Layer 3).

  Everything here is a command to the session process: start/pause/resume/end,
  trigger timeline elements, enter group decisions, resolve elections from a
  hand-count tally, adjudicate sidequests, and finally pick an ending from the
  recommendations. The board updates live via PubSub; a 1s tick keeps the game
  clock and deadline countdowns moving. Corrections are just re-entry (last
  wins) — click a different option and the board recomputes. The GM can also
  close a triggered element manually, deadline or not — undecided groups
  simply stay undecided, nothing is locked. Independent toggles control
  which sections appear on the scoreboard (projected display) — one per fixed
  section and one per per-participant value — plus one more
  for whether the group boards show each group's own values — this
  console's own board is never affected by any of them. The GM can also put
  a pre-authored full-screen page up on the scoreboard at any time,
  regardless of session status (before the show starts, onboarding) — a
  display override that doesn't pause or affect the game underneath.

  Layout: the page fills the window and never scrolls. A compact timeline
  list (left) selects the beat shown in the detail pane (middle) — pinned by
  `?beat=`, otherwise following the show; the room panel (right, a slide-in
  below `xl`) holds the board and every display control. Access & QR codes
  live in a slide-in drawer.
  """
  use ScenexWeb, :live_view

  alias Scenex.{Authoring, Play}
  alias Scenex.Engine.{Condition, Scale, Sim}
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} fill>
      <div
        id="console"
        class="flex h-full flex-col gap-3"
        phx-window-keydown={close_panels()}
        phx-key="Escape"
      >
        <%!-- Top bar: what the GM needs in an emergency, always in reach --%>
        <header class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-2 rounded-box bg-base-200 px-4 py-2">
          <h1 class="truncate text-lg font-semibold">{@session.label}</h1>
          <span class="badge badge-sm badge-accent badge-soft">GM console</span>
          <span id="session-status" class={["badge badge-sm", status_badge(@snap.status)]}>
            {@snap.status}
          </span>
          <span class="font-mono text-xl tabular-nums">{fmt_clock(@snap.game_time_ms)}</span>

          <div class="ml-auto flex flex-wrap items-center gap-2">
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
            <button
              :if={@snap.status == :paused}
              phx-click="resume"
              class="btn btn-sm btn-primary"
            >
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
            <span class="mx-1 hidden h-5 w-px bg-base-300 sm:block" />
            <button
              id="open-room"
              type="button"
              phx-click={open_room()}
              class="btn btn-sm btn-ghost xl:hidden"
            >
              📺 The room
            </button>
            <button
              id="open-access"
              type="button"
              phx-click={open_access()}
              class="btn btn-sm btn-ghost"
            >
              🔑 Access &amp; QR
            </button>
            <.link
              navigate={~p"/scenarios/#{@scenario.id}/sessions"}
              class="btn btn-sm btn-ghost"
            >
              ← Sessions
            </.link>
          </div>
        </header>

        <div
          :if={page = active_page(@snap)}
          id="page-warning"
          class="alert alert-warning shrink-0 py-2 text-sm"
        >
          <span>
            📄 The scoreboard is showing a page (<strong>{page.key}</strong>), not the live
            board — the session keeps running underneath.
          </span>
          <button type="button" phx-click="clear_page" class="btn btn-xs">
            ◼ Back to scoreboard
          </button>
        </div>

        <div class="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-y-auto lg:grid-cols-[16rem_minmax(0,1fr)] lg:overflow-hidden xl:grid-cols-[16rem_minmax(0,1fr)_25rem]">
          <%!-- Timeline: one compact row per beat, scrolls on its own --%>
          <nav
            id="timeline"
            phx-hook=".ActiveBeat"
            data-active={running_row_id(@snap)}
            class="min-h-0 rounded-box border border-base-300 bg-base-100 lg:overflow-y-auto"
          >
            <div class="sticky top-0 z-10 flex items-center justify-between border-b border-base-200 bg-base-100/95 px-3 py-2 backdrop-blur">
              <span class="text-xs font-semibold uppercase tracking-wider opacity-60">
                Timeline
              </span>
              <span class="text-xs tabular-nums opacity-50">
                {length(@snap.triggered)} / {length(@snap.definition.element_order)}
              </span>
            </div>
            <ol class="space-y-0.5 p-1.5">
              <li
                :for={element <- elements(@snap)}
                id={"beat-row-#{element.id}"}
                class={[
                  "group flex items-center gap-1 rounded-lg pr-1.5 transition-colors",
                  selected?(@selection, element) && "bg-primary/10 ring-1 ring-primary/30",
                  not selected?(@selection, element) && "hover:bg-base-200",
                  beat_state(@snap, element) == :closed && "opacity-55"
                ]}
              >
                <.link
                  patch={beat_path(@session, element.id)}
                  class="flex min-w-0 flex-1 items-center gap-2 py-1.5 pl-2"
                >
                  <.beat_mark
                    state={beat_state(@snap, element)}
                    decided={Play.element_decided?(@snap, element)}
                  />
                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-sm font-medium">
                      <span class="tabular-nums opacity-40">{element.position}.</span>
                      {I18n.t!(element.title, @locale, default: element.key)}
                    </span>
                    <span class="flex items-center gap-1.5 text-[11px] leading-tight opacity-60">
                      <span>{kind_label(element.kind)}</span>
                      <span :if={progress = decision_progress(@snap, element)}>· {progress}</span>
                      <span
                        :if={running_deadline?(@snap, element)}
                        class={["font-mono tabular-nums", deadline_text_class(@snap, element)]}
                      >
                        · ⏱ {fmt_deadline_left(deadline_left(@snap, element))}
                      </span>
                    </span>
                  </span>
                </.link>
                <button
                  :if={element.id not in @snap.triggered}
                  phx-click="trigger"
                  phx-value-id={element.id}
                  disabled={@snap.status not in [:live, :paused]}
                  title="Trigger"
                  class="btn btn-xs btn-square btn-primary btn-soft shrink-0 opacity-60 transition-opacity group-hover:opacity-100"
                >
                  ▶
                </button>
              </li>
              <li :if={@snap.status == :ended}>
                <.link
                  patch={beat_path(@session, "ending")}
                  class={[
                    "flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm font-medium",
                    (@selection == :ending && "bg-primary/10 ring-1 ring-primary/30") ||
                      "hover:bg-base-200"
                  ]}
                >
                  🏁 Choose the ending
                </.link>
              </li>
            </ol>
          </nav>

          <%!-- The selected beat: notes, decisions, effects, controls --%>
          <section
            id="beat-detail"
            class="min-h-0 rounded-box border border-base-300 bg-base-100 p-5 lg:overflow-y-auto"
          >
            <%= case @selection do %>
              <% :ending -> %>
                <.ending_panel snap={@snap} locale={@locale} />
              <% {:beat, element} -> %>
                <.beat_detail
                  element={element}
                  snap={@snap}
                  locale={@locale}
                  session={@session}
                  election_inputs={@election_inputs}
                />
              <% :none -> %>
                <p class="py-10 text-center text-sm opacity-60">
                  This scenario has no timeline yet.
                </p>
            <% end %>
          </section>

          <%!-- The room: what the audience and the groups see. A fixed column
          on wide screens, a slide-in panel below that. --%>
          <div
            id="room-backdrop"
            class="fixed inset-0 z-40 hidden bg-base-content/30"
            phx-click={close_panels()}
          />
          <aside
            id="room"
            class="hidden min-h-0 space-y-5 rounded-box border border-base-300 bg-base-100 p-4 xl:block xl:overflow-y-auto"
          >
            <div class="flex items-center justify-between xl:hidden">
              <h2 class="font-semibold">The room</h2>
              <button type="button" phx-click={close_panels()} class="btn btn-sm btn-ghost">
                ✕
              </button>
            </div>
            <.room_panel snap={@snap} locale={@locale} tally_inputs={@tally_inputs} />
          </aside>
        </div>
      </div>

      <%!-- Access & QR: mostly set up before the show, so out of the way --%>
      <div id="access-drawer" class="fixed inset-0 z-50 hidden">
        <div class="absolute inset-0 bg-base-content/30" phx-click={close_panels()} />
        <div class="absolute inset-y-0 right-0 flex w-full max-w-xl flex-col gap-4 overflow-y-auto bg-base-100 p-6 shadow-2xl">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-lg font-semibold">Access &amp; QR</h2>
            <div class="flex items-center gap-2">
              <.link
                href={~p"/sessions/#{@session.id}/qr_codes.pdf"}
                class="btn btn-xs btn-soft"
              >
                ⬇ Download all as PDF
              </.link>
              <button type="button" phx-click={close_panels()} class="btn btn-sm btn-ghost">
                ✕
              </button>
            </div>
          </div>
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
              + Code: {I18n.t!(g.name, @locale, default: g.key)}
            </button>
            <button
              :if={not has_display_token?(@tokens)}
              phx-click="gen_display_token"
              class="btn btn-xs"
            >
              + Code: projected display
            </button>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div :for={token <- @tokens} class="card bg-base-200">
              <div class="card-body items-center p-4">
                <span class="font-medium">{token_label(token, @locale)}</span>
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
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ActiveBeat">
        export default {
          mounted() { this.scroll() },
          updated() { if (this.el.dataset.active !== this.last) this.scroll() },
          scroll() {
            this.last = this.el.dataset.active
            const row = this.last && document.getElementById(this.last)
            if (row) row.scrollIntoView({ block: "nearest", behavior: "smooth" })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  # ── Components ────────────────────────────────────────────────────────

  attr :state, :atom, required: true
  attr :decided, :boolean, required: true

  defp beat_mark(assigns) do
    ~H"""
    <span class="flex w-4 shrink-0 justify-center text-xs">
      <%= cond do %>
        <% @decided -> %>
          <span class="text-success">✓</span>
        <% @state == :running -> %>
          <span class="relative flex size-2.5">
            <span class="absolute inline-flex size-full animate-ping rounded-full bg-primary opacity-60" />
            <span class="relative inline-flex size-2.5 rounded-full bg-primary" />
          </span>
        <% @state == :closed -> %>
          <span class="opacity-60">■</span>
        <% true -> %>
          <span class="size-2 rounded-full border border-base-content/30" />
      <% end %>
    </span>
    """
  end

  attr :element, :map, required: true
  attr :snap, :map, required: true
  attr :locale, :string, required: true
  attr :session, :map, required: true
  attr :election_inputs, :map, required: true

  defp beat_detail(assigns) do
    assigns =
      assign(assigns,
        triggered?: assigns.element.id in assigns.snap.triggered,
        closed?: assigns.element.id in assigns.snap.closed,
        running?: assigns.snap.status in [:live, :paused],
        next: next_beat(assigns.snap, assigns.element)
      )

    ~H"""
    <article id={"beat-#{@element.id}"} class="space-y-6">
      <div class="flex flex-wrap items-start gap-4">
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-1.5 text-xs">
            <span class="tabular-nums opacity-50">#{@element.position}</span>
            <span class="badge badge-sm">{kind_label(@element.kind)}</span>
            <span :if={@triggered?} class="badge badge-sm badge-primary badge-soft">triggered</span>
            <span
              :if={Play.element_decided?(@snap, @element)}
              class="badge badge-sm badge-success badge-soft"
            >
              decided
            </span>
            <span :if={@closed?} class="badge badge-sm badge-neutral badge-soft">closed</span>
            <span :if={running_deadline?(@snap, @element)} class={deadline_class(@snap, @element)}>
              ⏱ {fmt_deadline_left(deadline_left(@snap, @element))}
            </span>
          </div>
          <h2 class="mt-1.5 text-2xl font-bold leading-tight">
            {I18n.t!(@element.title, @locale, default: @element.key)}
          </h2>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            :if={not @triggered?}
            id={"trigger-#{@element.id}"}
            phx-click="trigger"
            phx-value-id={@element.id}
            disabled={not @running?}
            class="btn btn-primary"
          >
            ▶ Trigger
          </button>
          <button
            :if={@element.kind == :election and @triggered? and not @closed?}
            id={"toggle-ballot-#{@element.id}"}
            phx-click="toggle_ballot"
            phx-value-id={@element.id}
            disabled={not @running?}
            class={[
              "btn btn-sm",
              (@element.id in @snap.ballots_shown && "btn-primary") || "btn-ghost"
            ]}
            title="Show this vote's options on the scoreboard"
          >
            {if @element.id in @snap.ballots_shown,
              do: "👁 Options on screen",
              else: "🚫 Options on screen"}
          </button>
          <button
            :if={@triggered? and not @closed?}
            phx-click="close_element"
            phx-value-id={@element.id}
            disabled={not @running?}
            class="btn btn-sm btn-ghost"
            data-confirm="Close this event? Groups that haven't decided stay undecided — you can still enter a decision for them yourself afterward."
          >
            ⏹ Close event
          </button>
        </div>
      </div>

      <div
        :if={notes = notes(@element, @locale)}
        class="rounded-box border-l-4 border-accent bg-accent/5 px-4 py-3"
      >
        <div class="mb-1 text-xs font-semibold uppercase tracking-wider opacity-60">
          🎭 Director's notes
        </div>
        <.markdown text={notes} />
      </div>

      <details
        :if={description = I18n.t(@element.description, @locale)}
        class="group rounded-box bg-base-200/60 px-4 py-2"
      >
        <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wider opacity-60">
          What the room reads
        </summary>
        <div class="pt-2"><.markdown text={description} /></div>
      </details>

      <p
        :if={not @triggered?}
        class="rounded-box border border-dashed border-base-300 px-4 py-3 text-sm opacity-70"
      >
        Not triggered yet — the options below are a preview.
      </p>

      <%!-- Event: one decision per group --%>
      <div :if={@element.kind == :event} class="space-y-1">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">Decisions</h3>
        <div
          :for={g <- groups(@snap)}
          class="grid items-start gap-x-4 gap-y-2 border-t border-base-200 py-3 sm:grid-cols-[11rem_minmax(0,1fr)]"
        >
          <div class="flex items-center gap-1.5 pt-1 text-sm font-medium">
            <span class="truncate">{I18n.t!(g.name, @locale, default: g.key)}</span>
            <span :if={get_in(@snap.decisions, [@element.id, g.id])} class="text-success">✓</span>
          </div>
          <div class="flex flex-wrap gap-3">
            <div :for={o <- options_for_group(@snap, @element.id, g.id)} class="max-w-56 space-y-1">
              <button
                :if={@triggered?}
                phx-click="choose"
                phx-value-element={@element.id}
                phx-value-group={g.id}
                phx-value-option={o.id}
                disabled={not @running?}
                class={[
                  "btn btn-sm h-auto min-h-8 py-1 normal-case",
                  (decided?(@snap, @element.id, g.id, o.id) && "btn-primary") || "btn-outline"
                ]}
              >
                <.option_label option={o} />
              </button>
              <span :if={not @triggered?} class="badge badge-outline h-auto py-1">
                <.option_label option={o} />
              </span>
              <.effects option={o} snap={@snap} locale={@locale} />
            </div>
          </div>
        </div>
      </div>

      <%!-- Election: hand-count tally + winner --%>
      <form
        :if={@element.kind == :election}
        phx-submit="resolve_election"
        phx-change="election_change"
        class="space-y-3"
      >
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">Ballot</h3>
        <input type="hidden" name="element" value={@element.id} />
        <div
          :for={o <- options_for_element(@snap, @element.id)}
          class="grid items-center gap-3 rounded-box border border-base-200 px-3 py-2 sm:grid-cols-[minmax(0,1fr)_7rem]"
        >
          <label class="flex cursor-pointer items-start gap-3">
            <input
              type="radio"
              name="winner"
              value={o.id}
              checked={winner_choice(@election_inputs, @snap, @element.id) == o.id}
              disabled={not @triggered?}
              class="radio radio-sm mt-0.5"
            />
            <span class="min-w-0 space-y-0.5">
              <span class={[
                "block text-sm",
                decided?(@snap, @element.id, :winner, o.id) && "font-bold text-primary"
              ]}>
                <.option_label option={o} />
              </span>
              <.effects option={o} snap={@snap} locale={@locale} />
            </span>
          </label>
          <input
            type="number"
            name={"tally[#{o.id}]"}
            value={get_in(@election_inputs, [@element.id, "tally", o.id])}
            min="0"
            placeholder="votes"
            disabled={not @triggered?}
            class="input input-bordered input-sm w-28 text-right"
          />
        </div>
        <button
          :if={@triggered?}
          type="submit"
          disabled={not @running?}
          class="btn btn-sm btn-primary"
        >
          Declare result
        </button>
      </form>

      <%!-- Sidequest: adjudicate --%>
      <div :if={@element.kind == :sidequest} class="space-y-3">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">Adjudicate</h3>
        <div class="flex flex-wrap gap-3">
          <div :for={o <- options_for_element(@snap, @element.id)} class="max-w-64 space-y-1">
            <button
              :if={@triggered?}
              phx-click="adjudicate"
              phx-value-element={@element.id}
              phx-value-option={o.id}
              disabled={not @running?}
              class={[
                "btn btn-sm normal-case",
                (decided?(@snap, @element.id, :outcome, o.id) && "btn-primary") || "btn-outline"
              ]}
            >
              {o.outcome} — {o.key}
            </button>
            <span :if={not @triggered?} class="badge badge-outline">{o.outcome} — {o.key}</span>
            <.effects option={o} snap={@snap} locale={@locale} />
          </div>
        </div>
      </div>

      <div
        :if={@closed? and @next}
        class="flex justify-end border-t border-base-200 pt-4"
      >
        <.link patch={beat_path(@session, @next.id)} class="btn btn-sm btn-ghost">
          Next: {@next.position}. {I18n.t!(@next.title, @locale, default: @next.key)} →
        </.link>
      </div>
    </article>
    """
  end

  attr :option, :map, required: true

  defp option_label(assigns) do
    ~H"""
    {@option.key}
    <span :if={@option.is_default} class="badge badge-xs badge-ghost">default</span>
    <span :if={@option.condition} class="badge badge-xs badge-warning font-mono">
      {@option.condition}
    </span>
    """
  end

  attr :option, :map, required: true
  attr :snap, :map, required: true
  attr :locale, :string, required: true

  defp effects(assigns) do
    assigns = assign(assigns, :lines, effect_lines(assigns.option, assigns.snap, assigns.locale))

    ~H"""
    <p :if={@lines != []} class="flex flex-wrap gap-x-2 text-[11px] leading-snug">
      <span
        :for={{text, delta} <- @lines}
        class={[(delta > 0 && "text-success") || (delta < 0 && "text-error") || "opacity-60"]}
      >
        {text}
      </span>
    </p>
    """
  end

  attr :snap, :map, required: true
  attr :locale, :string, required: true
  attr :tally_inputs, :map, required: true

  defp room_panel(assigns) do
    ~H"""
    <section class="space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">Board</h3>
      <table class="table table-xs w-full table-fixed [&_td]:px-1 [&_th]:px-1">
        <thead>
          <tr>
            <th class="w-[34%]"></th>
            <th
              :for={vd <- value_dims(@snap)}
              class="truncate text-right"
              title={I18n.t!(vd.name, @locale, default: vd.key)}
            >
              {I18n.t!(vd.name, @locale, default: vd.key)}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={g <- groups(@snap)}>
            <td class="truncate font-medium" title={I18n.t!(g.name, @locale, default: g.key)}>
              {I18n.t!(g.name, @locale, default: g.key)}
            </td>
            <td
              :for={vd <- value_dims(@snap)}
              class={["whitespace-nowrap text-right tabular-nums", cell_class(@snap.sim, vd, g.id)]}
            >
              {fmt_num(Sim.get(@snap.sim, vd.id, g.id))}<.value_delta change={
                Play.recent_delta(@snap, vd.id, g.id)
              } />
            </td>
          </tr>
          <tr class="border-t-2 border-base-300 font-semibold">
            <td>Global</td>
            <td :for={vd <- value_dims(@snap)} class="whitespace-nowrap text-right tabular-nums">
              {fmt_num(@snap.globals[vd.id])}<.value_delta change={Play.recent_delta(@snap, vd.id)} />
            </td>
          </tr>
        </tbody>
      </table>
      <div :if={score = overall_index(@snap)} class="rounded bg-base-200 px-3 py-2 text-sm">
        <span class="font-semibold">{overall_index_label(@snap, @locale)}:</span>
        <span class="tabular-nums">{fmt_num(score)}</span>
        <span :if={overall_index_bands(@snap) != []} class="ml-1 opacity-70">
          ({overall_index_band_label(score, @snap, @locale)})
        </span>
        <span :if={overall_index_bands(@snap) == []} class="ml-1 opacity-50">
          (no bands defined yet — scoreboard section won't show)
        </span>
      </div>
    </section>

    <%!-- What the projected scoreboard shows; this console is never affected --%>
    <section class="space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">On the scoreboard</h3>
      <div class="flex flex-wrap gap-1.5">
        <button
          :for={{section, label} <- board_sections(@snap, @locale)}
          type="button"
          phx-click="toggle_board_section"
          phx-value-section={section}
          class={[
            "btn btn-xs",
            (Map.get(@snap.board_sections, section, true) && "btn-primary") || "btn-ghost"
          ]}
        >
          {if Map.get(@snap.board_sections, section, true), do: "👁 #{label}", else: "🚫 #{label}"}
        </button>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <button
          phx-click="toggle_board_numbers"
          class={["btn btn-xs", (@snap.show_numbers && "btn-primary") || "btn-ghost"]}
          title="Controls the projector and group screens — this console always shows numbers"
        >
          {if @snap.show_numbers,
            do: "🔢 Hide numbers on displays",
            else: "🔢 Show numbers on displays"}
        </button>
        <button
          :if={@snap.status in [:live, :paused]}
          type="button"
          phx-click="consolidate_values"
          class="btn btn-xs btn-ghost"
          title="Resets the audience bars' 'what changed' markers to right now — triggering the next element or closing this one also does this automatically"
        >
          ✓ Consolidate now
        </button>
      </div>
    </section>

    <section class="space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">On the group boards</h3>
      <button
        type="button"
        phx-click="toggle_group_values"
        class={["btn btn-xs", (@snap.group_values_visible && "btn-primary") || "btn-ghost"]}
      >
        {if @snap.group_values_visible, do: "👁 Group values", else: "🚫 Group values"}
      </button>
    </section>

    <%!-- Pre-authored full-screen pages, overriding the whole scoreboard;
    the game keeps running underneath --%>
    <section :if={pages(@snap) != []} class="space-y-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">Pages</h3>
      <div class="flex flex-wrap gap-1.5">
        <button
          :for={page <- pages(@snap)}
          type="button"
          phx-click="show_page"
          phx-value-id={page.id}
          class={["btn btn-xs", (@snap.active_page_id == page.id && "btn-primary") || "btn-soft"]}
        >
          {page.key}
        </button>
      </div>
    </section>

    <%!-- Per-participant values: hand-count tallies on each value's own scale --%>
    <section :for={vd <- participant_dims(@snap)} class="space-y-2">
      <div class="flex items-center gap-2">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60">
          {I18n.t!(vd.name, @locale, default: vd.key)} · hand count
        </h3>
        <span
          :if={avg = @snap.globals[vd.id]}
          class="ml-auto font-bold tabular-nums"
          title="Latest tally average"
        >
          {step_face(vd, avg)} {fmt_num(avg)}<.value_delta change={Play.recent_delta(@snap, vd.id)} />
        </span>
      </div>
      <form phx-submit="record_tally" phx-change="tally_change" class="space-y-2">
        <input type="hidden" name="value" value={vd.id} />
        <div class="flex gap-1.5">
          <label
            :for={{score, face, name} <- tally_scale(vd, @locale)}
            class="flex min-w-0 flex-1 flex-col items-center gap-0.5 text-xs"
            title={"#{name} (#{score})"}
          >
            <span>{face}</span>
            <input
              type="number"
              name={"counts[#{score}]"}
              value={get_in(@tally_inputs, [vd.id, to_string(score)])}
              min="0"
              placeholder="0"
              class="input input-bordered input-sm w-full px-1.5 text-right"
            />
          </label>
        </div>
        <button
          type="submit"
          disabled={@snap.status not in [:live, :paused]}
          class="btn btn-xs btn-primary"
        >
          Record tally
        </button>
      </form>
      <table :if={tally_history(@snap, vd.id) != []} class="table table-xs">
        <thead>
          <tr>
            <th>Time</th>
            <th :for={{_score, face, _name} <- tally_scale(vd, @locale)} class="text-right">
              {face}
            </th>
            <th class="text-right">Average</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- Enum.reverse(tally_history(@snap, vd.id))}>
            <td class="font-mono tabular-nums">{fmt_clock(entry.game_time_ms)}</td>
            <td
              :for={{score, _face, _name} <- tally_scale(vd, @locale)}
              class="text-right tabular-nums"
            >
              {entry.counts[score] || 0}
            </td>
            <td class="text-right font-semibold tabular-nums">
              {fmt_num(Sim.tally_mean(entry.counts))}
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  attr :snap, :map, required: true
  attr :locale, :string, required: true

  defp ending_panel(assigns) do
    ~H"""
    <div id="endings" class="space-y-4">
      <div>
        <h2 class="text-2xl font-bold">Choose the ending</h2>
        <p class="text-sm opacity-60">
          Recommendations from the final board — you have the last word.
        </p>
      </div>
      <ul class="space-y-2">
        <li
          :for={ending <- endings(@snap)}
          class={[
            "flex flex-wrap items-center gap-2 rounded-box bg-base-200 px-4 py-3",
            @snap.ending_id == ending.id && "ring-2 ring-primary"
          ]}
        >
          <span class="font-medium">{ending.key}</span>
          <span class="text-sm opacity-70">
            — {I18n.t!(ending.title, @locale, default: "—")}
          </span>
          <span :if={ending.condition} class="badge badge-xs font-mono">{ending.condition}</span>
          <span :if={recommended?(ending, @snap)} class="badge badge-sm badge-success">
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
    </div>
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
      Play.track_client(session.id, :gm)
      :timer.send_interval(1000, :tick)
    end

    {:ok,
     socket
     |> assign(
       session: session,
       scenario: scenario,
       locale: session.locale || scenario.source_locale,
       page_title: "Console — #{session.label}",
       snap: Play.snapshot(session.id),
       tokens: Play.list_tokens(session),
       tally_inputs: %{},
       election_inputs: %{},
       beat: nil
     )}
  end

  # `?beat=<element id>` (or `ending`) pins the detail pane; without it the
  # pane follows the show — the running beat, else the next one up.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:beat, params["beat"]) |> assign_selection()}
  end

  # ── Commands ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("start", _params, socket), do: run(socket, &Play.start_session/1)
  def handle_event("pause", _params, socket), do: run(socket, &Play.pause_session/1)
  def handle_event("resume", _params, socket), do: run(socket, &Play.resume_session/1)

  def handle_event("end_session", _params, socket) do
    run(
      socket,
      &Play.end_session/1,
      &push_patch(&1, to: beat_path(&1.assigns.session, "ending"))
    )
  end

  def handle_event("toggle_board_numbers", _params, socket) do
    run(socket, &Play.set_board_numbers(&1, not socket.assigns.snap.show_numbers))
  end

  def handle_event("consolidate_values", _params, socket),
    do: run(socket, &Play.consolidate_values/1)

  def handle_event("show_page", %{"id" => page_id}, socket),
    do: run(socket, &Play.show_page(&1, page_id))

  def handle_event("clear_page", _params, socket), do: run(socket, &Play.clear_page/1)

  def handle_event("toggle_board_section", %{"section" => section}, socket) do
    visible = not section_visible?(socket.assigns.snap, section)
    run(socket, &Play.set_board_section(&1, section, visible))
  end

  def handle_event("toggle_group_values", _params, socket) do
    run(socket, &Play.set_group_values_visible(&1, not socket.assigns.snap.group_values_visible))
  end

  def handle_event("trigger", %{"id" => element_id}, socket) do
    run(
      socket,
      &Play.trigger_element(&1, element_id),
      &push_patch(&1, to: beat_path(&1.assigns.session, element_id))
    )
  end

  def handle_event("toggle_ballot", %{"id" => element_id}, socket) do
    visible = element_id not in socket.assigns.snap.ballots_shown
    run(socket, &Play.set_ballot_visible(&1, element_id, visible))
  end

  def handle_event("close_element", %{"id" => element_id}, socket),
    do: run(socket, &Play.close_element(&1, element_id))

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
    case socket.assigns.snap.definition.groups[group_id] do
      nil ->
        {:noreply, put_flash(socket, :error, "This group is not part of this session.")}

      group ->
        {:ok, _token} = Play.create_group_token(socket.assigns.session, group)
        {:noreply, reload_tokens(socket)}
    end
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
        {:noreply, socket |> assign(:snap, snapshot) |> assign_selection() |> on_success.()}

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
    socket
    |> assign(:snap, Play.snapshot(socket.assigns.session.id))
    |> assign_selection()
  end

  defp assign_selection(socket),
    do: assign(socket, :selection, selection(socket.assigns.snap, socket.assigns.beat))

  defp selection(%{status: :ended}, "ending"), do: :ending

  defp selection(snap, beat) when is_binary(beat) and is_map_key(snap.definition.elements, beat),
    do: {:beat, snap.definition.elements[beat]}

  defp selection(%{status: :ended}, _beat), do: :ending

  defp selection(snap, _beat) do
    case running_element(snap) || next_untriggered(snap) || List.last(elements(snap)) do
      nil -> :none
      element -> {:beat, element}
    end
  end

  # The latest triggered element that isn't closed yet.
  defp running_element(snap) do
    case Enum.find(Enum.reverse(snap.triggered), &(&1 not in snap.closed)) do
      nil -> nil
      id -> snap.definition.elements[id]
    end
  end

  defp next_untriggered(snap), do: Enum.find(elements(snap), &(&1.id not in snap.triggered))

  defp next_beat(snap, element) do
    snap
    |> elements()
    |> Enum.drop_while(&(&1.id != element.id))
    |> Enum.drop(1)
    |> Enum.find(&(&1.id not in snap.triggered))
  end

  # ── Layout helpers ────────────────────────────────────────────────────

  defp beat_path(session, beat), do: ~p"/sessions/#{session.id}/console?beat=#{beat}"

  defp selected?({:beat, %{id: id}}, %{id: id}), do: true
  defp selected?(_selection, _element), do: false

  defp beat_state(snap, element) do
    cond do
      element.id in snap.closed -> :closed
      element.id in snap.triggered -> :running
      true -> :pending
    end
  end

  defp running_row_id(snap) do
    case running_element(snap) do
      nil -> nil
      element -> "beat-row-#{element.id}"
    end
  end

  defp active_page(%{active_page_id: nil}), do: nil
  defp active_page(snap), do: snap.definition.pages[snap.active_page_id]

  # "3/5 decided" for a triggered event; nothing for other kinds.
  defp decision_progress(snap, %{kind: :event} = element) do
    if element.id in snap.triggered do
      decided = map_size(snap.decisions[element.id] || %{})
      "#{decided}/#{length(snap.definition.group_ids)} decided"
    end
  end

  defp decision_progress(_snap, _element), do: nil

  defp running_deadline?(snap, element) do
    deadline_left(snap, element) != nil and element.id not in snap.closed and
      not Play.element_decided?(snap, element)
  end

  defp deadline_text_class(snap, element) do
    left = deadline_left(snap, element)

    cond do
      left <= 0 -> "text-error"
      left < 60_000 -> "text-warning"
      true -> ""
    end
  end

  # One `{"+2 Life Support (Science)", delta}` per effect. A nil group means
  # the deciding group; effects aimed at groups outside this session no-op,
  # so they aren't listed.
  defp effect_lines(option, snap, locale) do
    dims = Map.new(snap.definition.value_dimensions, &{&1.id, &1})

    for effect <- option.effects,
        vd = dims[effect.value_dimension_id],
        is_nil(effect.group_id) or Map.has_key?(snap.definition.groups, effect.group_id) do
      target =
        case snap.definition.groups[effect.group_id] do
          nil -> ""
          group -> " (#{I18n.t!(group.name, locale, default: group.key)})"
        end

      {"#{fmt_delta(effect.delta)} #{I18n.t!(vd.name, locale, default: vd.key)}#{target}",
       effect.delta}
    end
  end

  defp fmt_delta(delta) when delta > 0, do: "+" <> fmt_num(delta)
  defp fmt_delta(delta) when delta < 0, do: "−" <> fmt_num(abs(delta))
  defp fmt_delta(delta), do: fmt_num(delta)

  @room_open "fixed inset-y-0 right-0 z-50 w-full max-w-md overflow-y-auto rounded-none shadow-2xl"

  defp open_room do
    JS.remove_class("hidden", to: "#room")
    |> JS.add_class(@room_open, to: "#room")
    |> JS.remove_class("hidden", to: "#room-backdrop")
  end

  defp open_access, do: JS.remove_class("hidden", to: "#access-drawer")

  defp close_panels do
    JS.add_class("hidden", to: "#room")
    |> JS.remove_class(@room_open, to: "#room")
    |> JS.add_class("hidden", to: "#room-backdrop")
    |> JS.add_class("hidden", to: "#access-drawer")
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

  # Fixed sections (atom-keyed) plus one per per-participant value (keyed by id
  # string). The key type matches how the projection stores each section, so a
  # single Map.get lookup covers both.
  defp board_sections(snap, locale) do
    participant =
      for vd <- participant_dims(snap), do: {vd.id, I18n.t!(vd.name, locale, default: vd.key)}

    [{:globals, "Global values"}] ++
      participant ++
      [
        {:overall_index,
         I18n.t!(snap.definition.overall_index_name, locale, default: "Overall Index")},
        {:current_beat, "Current event"}
      ]
  end

  # Current visibility of a section given the string that arrives from the
  # toggle: fixed sections resolve to their atom key, per-participant sections
  # stay string ids. Absent = visible (the default for a value never toggled).
  @fixed_sections ~w(globals overall_index current_beat)
  defp section_visible?(snap, section) when is_binary(section) do
    key = if section in @fixed_sections, do: String.to_existing_atom(section), else: section
    Map.get(snap.board_sections, key, true)
  end

  defp pages(snap), do: snap.definition.pages |> Map.values() |> Enum.sort_by(& &1.position)

  defp value_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_group))

  defp participant_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_participant))

  defp tally_history(snap, value_id), do: snap.tallies[value_id] || []

  # ── Overall Index ─────────────────────────────────────────────────────

  defp overall_index(snap) do
    case Play.overall_index(snap) do
      {:ok, score} -> score
      _ -> nil
    end
  end

  defp overall_index_bands(snap), do: snap.definition.overall_index_bands

  defp overall_index_label(snap, locale),
    do: I18n.t!(snap.definition.overall_index_name, locale, default: "Overall Index")

  # `overall_index_bands` is worst-to-best (position ascending, how they're
  # authored); Scale.label/4 wants best-to-worst.
  defp overall_index_band_label(score, snap, locale) do
    labels =
      overall_index_bands(snap)
      |> Enum.reverse()
      |> Enum.map(&I18n.t!(&1.name, locale, default: "—"))

    Scale.label(
      score,
      snap.definition.overall_index_min,
      snap.definition.overall_index_max,
      labels
    )
  end

  # The value's own steps as `{score, emoji}`, best score first (how the tally
  # entry and history columns read). Steps are authored worst-to-best.
  defp tally_scale(vd, locale) do
    vd.steps
    |> Enum.sort_by(& &1.position, :desc)
    |> Enum.map(&{&1.position, &1.emoji, I18n.t!(&1.name, locale, default: "")})
  end

  # The step emoji standing for a mean: steps are worst-to-best, Scale.label/4
  # wants best-to-worst. No steps yet -> nothing to show.
  defp step_face(%{steps: [_ | _] = steps}, avg) when is_number(avg) do
    emojis = steps |> Enum.map(& &1.emoji) |> Enum.reverse()
    Scale.label(avg, 1.0, length(steps) * 1.0, emojis)
  end

  defp step_face(_vd, _avg), do: ""

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
    do: I18n.t!(group.name, locale, default: group.key)

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
