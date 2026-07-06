defmodule ScenexWeb.PlayLive.Group do
  @moduledoc """
  The group input view — opened via a QR capability token, no login.

  The token authorizes **exactly one group in exactly one session**; the group
  id comes from the token, never from the client. The table sees its own
  values plus the globals, and enters its decision on each triggered event
  element. Gates are enforced here (players cannot pick locked options — only
  the GM may override in the console), and a lapsed deadline closes the
  element.

  A decision is **confirmed once**: tapping an option opens a styled confirm
  modal (a pending choice held in assigns — no native `window.confirm`), and
  confirming locks the element for this group — corrections are the GM's
  alone. The lock derives from the projection ("a decision exists"), so a GM
  entry or a lapsed-deadline default locks the group out the same way.
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
              phx-click="select"
              phx-value-element={element.id}
              phx-value-option={option.id}
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

      <%!-- Styled confirm dialog for the pending choice --%>
      <div :if={option = pending_option(@snap, @pending)} class="modal modal-open" role="dialog">
        <div class="modal-box space-y-4">
          <h3 class="text-xl font-bold">Lock in your decision?</h3>
          <p class="rounded-box bg-base-200 p-3 text-base font-medium">
            {I18n.t!(option.text, @locale, default: option.handle)}
          </p>
          <p class="text-sm opacity-70">
            Your group cannot change this afterwards — only the game master can.
          </p>
          <div class="modal-action">
            <button phx-click="cancel_choice" class="btn btn-lg">Cancel</button>
            <button
              phx-click="choose"
              phx-value-element={@pending.element_id}
              phx-value-option={@pending.option_id}
              class="btn btn-lg btn-primary"
            >
              Confirm decision
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel_choice"></div>
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
           snap: snap,
           pending: nil
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

  # Step 1: the tap — hold the choice as pending and open the confirm modal.
  @impl true
  def handle_event("select", %{"element" => element_id, "option" => option_id}, socket) do
    case choice_error(socket.assigns.snap, element_id, option_id, socket.assigns.group.id) do
      nil ->
        {:noreply, assign(socket, :pending, %{element_id: element_id, option_id: option_id})}

      :ignore ->
        {:noreply, socket}

      message ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("cancel_choice", _params, socket),
    do: {:noreply, assign(socket, :pending, nil)}

  # Step 2: the confirmation — re-validated, since the board may have moved
  # (GM entry, lapsed deadline, pause) while the modal was open.
  def handle_event("choose", %{"element" => element_id, "option" => option_id}, socket) do
    socket = assign(socket, :pending, nil)

    case choice_error(socket.assigns.snap, element_id, option_id, socket.assigns.group.id) do
      nil ->
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

      :ignore ->
        {:noreply, socket}

      message ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_info({:session_updated, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(:tick, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    socket
    |> assign(:snap, Play.snapshot(socket.assigns.session_id))
    |> drop_stale_pending()
  end

  # Close an open confirm modal when its choice stops being valid (GM entry,
  # lapsed deadline, pause) — better than confirming into a rejection.
  defp drop_stale_pending(%{assigns: %{pending: nil}} = socket), do: socket

  defp drop_stale_pending(%{assigns: %{pending: pending}} = socket) do
    case choice_error(
           socket.assigns.snap,
           pending.element_id,
           pending.option_id,
           socket.assigns.group.id
         ) do
      nil -> socket
      _ -> assign(socket, :pending, nil)
    end
  end

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

  # Why a choice can't proceed: an error message, `:ignore` for garbage
  # ids, or nil when it's allowed.
  defp choice_error(snap, element_id, option_id, group_id) do
    element = snap.definition.elements[element_id]
    option = snap.definition.options[option_id]

    cond do
      is_nil(element) or is_nil(option) ->
        :ignore

      locked?(snap, element_id, group_id) ->
        "Your decision is locked — ask the game master to change it."

      not choosable?(snap, element, option, group_id) ->
        "This option can't be chosen right now."

      true ->
        nil
    end
  end

  defp pending_option(_snap, nil), do: nil
  defp pending_option(snap, %{option_id: option_id}), do: snap.definition.options[option_id]

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
