defmodule ScenexWeb.PlayLive.Group do
  @moduledoc """
  The group input view — opened via a QR capability token, no login.

  The token authorizes **exactly one group in exactly one session**; the group
  id comes from the token, never from the client. The table sees its own
  values plus the globals, and enters its decision on each triggered event
  element. Gates are enforced here (players cannot pick locked options — only
  the GM may override in the console), and a lapsed deadline closes the
  element.

  A decision is **confirmed once**: after the table locks it in (native
  confirm dialog), the element closes for this group — corrections are the
  GM's alone. The lock derives from the projection ("a decision exists"), so
  a GM entry or a lapsed-deadline default locks the group out the same way.
  """
  use ScenexWeb, :live_view

  alias Scenex.Play
  alias Scenex.Engine.Sim
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.play flash={@flash}>
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h1 class="text-3xl font-bold">
          {I18n.t!(@group.name, @locale, default: @group.handle)}
        </h1>
        <div class="flex items-center gap-3">
          <span class={["badge", status_badge(@snap.status)]}>{@snap.status}</span>
          <span class="font-mono text-2xl tabular-nums">{fmt_clock(@snap.game_time_ms)}</span>
        </div>
      </div>

      <%!-- Own values + globals --%>
      <div class="mt-4 overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th></th>
              <th :for={vd <- value_dims(@snap)} class="text-right text-base">
                {I18n.t!(vd.name, @locale, default: vd.key)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="text-lg font-medium">
                {I18n.t!(@group.name, @locale, default: @group.handle)}
              </td>
              <td
                :for={vd <- value_dims(@snap)}
                class="text-right text-lg tabular-nums font-semibold"
              >
                {fmt_num(Sim.get(@snap.sim, vd.id, @group.id))}
              </td>
            </tr>
            <tr class="opacity-70">
              <td>Global</td>
              <td :for={vd <- value_dims(@snap)} class="text-right text-lg tabular-nums">
                {fmt_num(@snap.globals[vd.id])}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@snap.status == :draft} class="mt-8 text-center text-lg opacity-70">
        The session hasn't started yet — hold tight.
      </p>

      <p :if={@snap.status == :paused} class="mt-8 text-center text-lg opacity-70">
        ⏸ The session is paused — decisions reopen when play resumes.
      </p>

      <p :if={@snap.status == :ended} class="mt-8 text-center text-lg opacity-70">
        The session has ended. Thank you for playing.
      </p>

      <%!-- Open decisions, newest first --%>
      <div class="mt-8 space-y-6">
        <section
          :for={element <- my_elements(@snap, @group.id)}
          class="rounded-box border border-base-300 p-4 space-y-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-xl font-semibold">
              {I18n.t!(element.title, @locale, default: element.handle)}
            </h3>
            <span :if={deadline_left(@snap, element)} class={deadline_class(@snap, element)}>
              ⏱ {fmt_deadline_left(deadline_left(@snap, element))}
            </span>
          </div>

          <p
            :if={narrative = I18n.t(element.narrative, @locale)}
            class="whitespace-pre-line text-base"
          >
            {narrative}
          </p>

          <div class="flex flex-col gap-3">
            <button
              :for={option <- my_options(@snap, element.id, @group.id)}
              phx-click="choose"
              phx-value-element={element.id}
              phx-value-option={option.id}
              data-confirm={"Lock in “#{I18n.t!(option.text, @locale, default: option.handle)}”? Your group cannot change this afterwards."}
              disabled={
                not choosable?(@snap, element, option, @group.id) and
                  not chosen?(@snap, element.id, @group.id, option.id)
              }
              class={[
                "btn h-auto min-h-14 justify-start py-3 text-left text-base normal-case",
                chosen?(@snap, element.id, @group.id, option.id) &&
                  "btn-primary pointer-events-none",
                locked?(@snap, element.id, @group.id) &&
                  not chosen?(@snap, element.id, @group.id, option.id) && "opacity-40",
                not Play.gate_open?(@snap, element.id, option) && "btn-disabled opacity-60"
              ]}
            >
              <span>
                {I18n.t!(option.text, @locale, default: option.handle)}
                <span :for={l <- option.labels} class={["badge badge-xs ml-1", label_class(l.color)]}>
                  {l.icon || I18n.t!(l.name, @locale, default: "?")}
                </span>
                <span
                  :if={not Play.gate_open?(@snap, element.id, option)}
                  class="ml-1 text-xs font-mono opacity-70"
                >
                  🔒 {option.condition}
                </span>
              </span>
            </button>
          </div>

          <p
            :if={locked?(@snap, element.id, @group.id)}
            class="text-sm font-medium text-success"
          >
            ✓ Decision confirmed — only the game master can change it now.
          </p>

          <p
            :if={expired?(@snap, element) and not locked?(@snap, element.id, @group.id)}
            class="text-xs opacity-60"
          >
            The deadline has passed — this decision is closed.
          </p>
        </section>
      </div>
    </Layouts.play>
    """
  end

  @impl true
  def mount(%{"token" => token_string}, _session, socket) do
    case Play.fetch_token(token_string) do
      {:ok, %{kind: :group} = token} ->
        if connected?(socket) do
          Play.subscribe(token.session_id)
          :timer.send_interval(1000, :tick)
        end

        snap = Play.snapshot(token.session_id)
        scenario_locale = snap.definition.value_dimensions |> locale_from(token)

        {:ok,
         socket
         |> assign(
           token: token,
           group: token.group,
           session_id: token.session_id,
           locale: scenario_locale,
           page_title: token.group.handle,
           snap: snap
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "This code is not valid (anymore).")
         |> push_navigate(to: ~p"/")}
    end
  end

  # v1: play in the session's source locale.
  defp locale_from(_value_dimensions, token) do
    Scenex.Authoring.get_scenario!(token.session.scenario_id).source_locale
  end

  @impl true
  def handle_event("choose", %{"element" => element_id, "option" => option_id}, socket) do
    snap = socket.assigns.snap
    element = snap.definition.elements[element_id]
    option = snap.definition.options[option_id]

    cond do
      is_nil(element) or is_nil(option) ->
        {:noreply, socket}

      locked?(snap, element_id, socket.assigns.group.id) ->
        {:noreply,
         put_flash(socket, :error, "Your decision is locked — ask the game master to change it.")}

      not choosable?(snap, element, option, socket.assigns.group.id) ->
        {:noreply, put_flash(socket, :error, "This option can't be chosen right now.")}

      true ->
        # The group id comes from the token — never from the client.
        case Play.choose_option(
               socket.assigns.session_id,
               element_id,
               socket.assigns.group.id,
               option_id
             ) do
          {:ok, snap} ->
            {:noreply, assign(socket, :snap, snap)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Rejected: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_info({:session_updated, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(:tick, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket), do: assign(socket, :snap, Play.snapshot(socket.assigns.session_id))

  # ── Rules ─────────────────────────────────────────────────────────────

  defp choosable?(snap, element, option, group_id) do
    snap.status == :live and
      not locked?(snap, element.id, group_id) and
      not expired?(snap, element) and
      Play.gate_open?(snap, element.id, option)
  end

  # Confirmed once: any recorded decision (the group's, the GM's, or a
  # lapsed-deadline default) closes the element for this group.
  defp locked?(snap, element_id, group_id),
    do: get_in(snap.decisions, [element_id, group_id]) != nil

  defp expired?(snap, element) do
    case deadline_left(snap, element) do
      nil -> false
      left -> left <= 0
    end
  end

  # ── Snapshot accessors ────────────────────────────────────────────────

  defp value_dims(snap),
    do: Enum.filter(snap.definition.value_dimensions, &(&1.input_scope == :per_group))

  # Triggered event-kind elements where this group has options, newest first.
  defp my_elements(snap, group_id) do
    for eid <- Enum.reverse(snap.triggered),
        element = snap.definition.elements[eid],
        element.kind == :event,
        my_options(snap, eid, group_id) != [],
        do: element
  end

  defp my_options(snap, element_id, group_id) do
    (snap.definition.options_by_element[element_id] || [])
    |> Enum.filter(&(&1.group_id == group_id))
  end

  defp chosen?(snap, element_id, group_id, option_id),
    do: get_in(snap.decisions, [element_id, group_id]) == option_id

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

  defp fmt_deadline_left(ms) when ms <= 0, do: "closed"
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

  defp fmt_num(nil), do: "—"

  defp fmt_num(n) when is_float(n) do
    rounded = Float.round(n, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end

  defp fmt_num(n), do: to_string(n)

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
