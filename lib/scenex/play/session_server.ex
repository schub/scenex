defmodule Scenex.Play.SessionServer do
  @moduledoc """
  One process per running session (Layer 3).

  Holds the definition snapshot and the current projection. Every command is
  validated against the projection, appended to the **append-only log** and
  (where operational state changes) written to the session row in one
  transaction, folded into the in-memory projection, and broadcast via PubSub.

  **Crash recovery = replay:** `init/1` re-reads the session row, the
  definition, and the whole log, and folds it back into the identical board.

  Timers run against the **pausable game clock**: `game_time_ms` accumulates
  while live; every appended event is stamped with the current game time.
  """
  use GenServer, restart: :transient

  import Ecto.Query, warn: false

  alias Scenex.Authoring
  alias Scenex.Play.{Definition, Projection, Session, SessionEvent}
  alias Scenex.Repo

  # ── Client API ────────────────────────────────────────────────────────

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via(session_id))
  end

  def via(session_id), do: {:via, Registry, {Scenex.Play.Registry, session_id}}

  def whereis(session_id) do
    case Registry.lookup(Scenex.Play.Registry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Execute a command; returns `{:ok, snapshot}` or `{:error, reason}`."
  def command(session_id, command), do: GenServer.call(via(session_id), {:command, command})

  @doc "The current board: status, sim, globals, decisions, clock."
  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)

  # ── Server ────────────────────────────────────────────────────────────

  @impl true
  def init(session_id) do
    session = Repo.get!(Session, session_id)

    definition =
      Definition.load(
        Authoring.get_scenario!(session.scenario_id),
        Scenex.Play.session_group_ids(session)
      )

    events =
      Repo.all(from e in SessionEvent, where: e.session_id == ^session_id, order_by: e.sequence)

    projection = Enum.reduce(events, Projection.new(definition), &Projection.apply_event(&2, &1))
    sequence = events |> List.last() |> then(&((&1 && &1.sequence) || 0))

    state = %{
      session: session,
      definition: definition,
      projection: projection,
      seq: sequence,
      timers: %{}
    }

    {:ok, schedule_deadlines(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  def handle_call({:command, command}, _from, state) do
    case validate(command, state) do
      {:ok, type, payload, row_changes} ->
        case persist(state, type, payload, row_changes) do
          {:ok, state} ->
            state = schedule_deadlines(state)
            broadcast(state)
            {:reply, {:ok, build_snapshot(state)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:deadline, element_id}, state) do
    {:noreply, fire_deadline(state, element_id)}
  end

  # ── Deadline timers ───────────────────────────────────────────────────
  # Timers run against the game clock: scheduled only while :live, cancelled
  # on pause, rescheduled with the remaining game time on resume/restart.
  # A lapsed deadline appends the authored default option for every still-
  # undecided slot (event kind: per group; election: the default ballot
  # option). Sidequests have no defaults — the GM adjudicates.

  defp schedule_deadlines(state) do
    state = cancel_timers(state)

    if state.projection.status == :live do
      timers =
        for {element_id, remaining_ms} <- pending_deadlines(state), into: %{} do
          {element_id, Process.send_after(self(), {:deadline, element_id}, max(remaining_ms, 0))}
        end

      %{state | timers: timers}
    else
      state
    end
  end

  defp cancel_timers(state) do
    Enum.each(state.timers, fn {_id, ref} -> Process.cancel_timer(ref) end)
    %{state | timers: %{}}
  end

  defp pending_deadlines(state) do
    game_time = current_game_time(state.session)

    for element_id <- state.projection.triggered,
        element = state.definition.elements[element_id],
        is_integer(element.deadline_seconds),
        missing_defaults(state, element) != [],
        deadline_at = state.projection.triggered_at[element_id] + element.deadline_seconds * 1000,
        do: {element_id, deadline_at - game_time}
  end

  # The default decisions a lapsed deadline would apply right now.
  defp missing_defaults(state, element) do
    options = state.definition.options_by_element[element.id] || []
    decided = Map.get(state.projection.decisions, element.id, %{})

    case element.kind do
      :event ->
        for option <- options,
            option.is_default,
            not Map.has_key?(decided, option.group_id),
            do: {option.group_id, option.id}

      :election ->
        with false <- Map.has_key?(decided, :winner),
             %{id: option_id} <- Enum.find(options, & &1.is_default) do
          [{:winner, option_id}]
        else
          _ -> []
        end

      :sidequest ->
        []
    end
  end

  defp fire_deadline(state, element_id) do
    element = state.definition.elements[element_id]

    if state.projection.status == :live and element do
      state =
        Enum.reduce(missing_defaults(state, element), state, fn {slot, option_id}, acc ->
          payload =
            case slot do
              :winner -> %{element_id: element_id, option_id: option_id}
              group_id -> %{element_id: element_id, group_id: group_id, option_id: option_id}
            end

          case persist(acc, "deadline_lapsed", payload, %{}) do
            {:ok, acc2} -> acc2
            {:error, _reason} -> acc
          end
        end)

      broadcast(state)
      schedule_deadlines(state)
    else
      state
    end
  end

  # ── Command validation ────────────────────────────────────────────────
  # Structural integrity is enforced; gates are not (the GM disposes).

  defp validate({:start}, %{projection: %{status: :draft}}),
    do: {:ok, "session_started", %{}, %{status: :live, clock_started_at: now()}}

  defp validate({:start}, _state), do: {:error, :already_started}

  defp validate({:pause}, %{projection: %{status: :live}} = state) do
    {:ok, "session_paused", %{},
     %{status: :paused, game_time_ms: current_game_time(state.session), clock_started_at: nil}}
  end

  defp validate({:pause}, _state), do: {:error, :not_live}

  defp validate({:resume}, %{projection: %{status: :paused}}),
    do: {:ok, "session_resumed", %{}, %{status: :live, clock_started_at: now()}}

  defp validate({:resume}, _state), do: {:error, :not_paused}

  defp validate({:end_session}, %{projection: %{status: status}} = state)
       when status in [:live, :paused] do
    {:ok, "session_ended", %{},
     %{status: :ended, game_time_ms: current_game_time(state.session), clock_started_at: nil}}
  end

  defp validate({:end_session}, _state), do: {:error, :not_running}

  defp validate({:select_ending, ending_id}, %{projection: %{status: :ended}} = state) do
    if Enum.any?(state.definition.endings, &(&1.id == ending_id)),
      do: {:ok, "ending_selected", %{ending_id: ending_id}, %{ending_id: ending_id}},
      else: {:error, :unknown_ending}
  end

  defp validate({:select_ending, _}, _state), do: {:error, :not_ended}

  defp validate({:trigger_element, element_id}, state) do
    with :ok <- running(state),
         {:ok, _element} <- fetch_element(state, element_id) do
      if element_id in state.projection.triggered,
        do: {:error, :already_triggered},
        else: {:ok, "element_triggered", %{element_id: element_id}, %{}}
    end
  end

  defp validate({:choose_option, element_id, group_id, option_id}, state) do
    with :ok <- running(state),
         {:ok, element} <- fetch_triggered(state, element_id),
         :ok <- expect_kind(element, :event),
         {:ok, option} <- fetch_option(state, element_id, option_id) do
      if option.group_id == group_id,
        do:
          {:ok, "option_chosen",
           %{element_id: element_id, group_id: group_id, option_id: option_id}, %{}},
        else: {:error, :option_not_for_group}
    end
  end

  defp validate({:resolve_election, element_id, option_id, tally}, state) do
    with :ok <- running(state),
         {:ok, element} <- fetch_triggered(state, element_id),
         :ok <- expect_kind(element, :election),
         {:ok, _option} <- fetch_option(state, element_id, option_id) do
      {:ok, "election_resolved",
       %{element_id: element_id, option_id: option_id, tally: tally || %{}}, %{}}
    end
  end

  defp validate({:adjudicate_sidequest, element_id, option_id}, state) do
    with :ok <- running(state),
         {:ok, element} <- fetch_triggered(state, element_id),
         :ok <- expect_kind(element, :sidequest),
         {:ok, _option} <- fetch_option(state, element_id, option_id) do
      {:ok, "sidequest_adjudicated", %{element_id: element_id, option_id: option_id}, %{}}
    end
  end

  defp validate({:record_tally, value_id, counts}, state) do
    with :ok <- running(state),
         :ok <- fetch_per_participant(state, value_id),
         :ok <- valid_tally(counts) do
      {:ok, "tally_recorded", %{value_id: value_id, counts: counts}, %{}}
    end
  end

  defp validate(_command, _state), do: {:error, :unknown_command}

  defp running(%{projection: %{status: status}}) when status in [:live, :paused], do: :ok
  defp running(_state), do: {:error, :not_running}

  defp fetch_element(state, element_id) do
    case state.definition.elements[element_id] do
      nil -> {:error, :unknown_element}
      element -> {:ok, element}
    end
  end

  defp fetch_triggered(state, element_id) do
    with {:ok, element} <- fetch_element(state, element_id) do
      if element_id in state.projection.triggered,
        do: {:ok, element},
        else: {:error, :not_triggered}
    end
  end

  defp expect_kind(%{kind: kind}, kind), do: :ok
  defp expect_kind(%{kind: actual}, _expected), do: {:error, {:wrong_kind, actual}}

  defp fetch_option(state, element_id, option_id) do
    case state.definition.options[option_id] do
      %{timeline_element_id: ^element_id} = option -> {:ok, option}
      _ -> {:error, :unknown_option}
    end
  end

  defp fetch_per_participant(state, value_id) do
    case Enum.find(state.definition.specs, &(&1.key == value_id)) do
      nil -> {:error, :unknown_value}
      %{input_scope: :per_participant} -> :ok
      %{} -> {:error, :not_per_participant}
    end
  end

  # A tally is `%{score => count}` (scores as integers or integer strings —
  # form params arrive stringly); at least one participant must be counted.
  defp valid_tally(counts) when is_map(counts) and map_size(counts) > 0 do
    entries_ok =
      Enum.all?(counts, fn {score, count} ->
        valid_score?(score) and is_integer(count) and count >= 0
      end)

    cond do
      not entries_ok -> {:error, :invalid_tally}
      counts |> Map.values() |> Enum.sum() == 0 -> {:error, :empty_tally}
      true -> :ok
    end
  end

  defp valid_tally(_counts), do: {:error, :invalid_tally}

  defp valid_score?(score) when is_integer(score), do: true
  defp valid_score?(score) when is_binary(score), do: match?({_, ""}, Integer.parse(score))
  defp valid_score?(_score), do: false

  # ── Persistence ───────────────────────────────────────────────────────

  defp persist(state, type, payload, row_changes) do
    event_changeset =
      SessionEvent.changeset(%SessionEvent{}, %{
        session_id: state.session.id,
        sequence: state.seq + 1,
        type: type,
        payload: payload,
        game_time_ms: current_game_time(state.session)
      })

    result =
      Repo.transaction(fn ->
        event = Repo.insert!(event_changeset)

        session =
          if row_changes == %{},
            do: state.session,
            else: Repo.update!(Ecto.Changeset.change(state.session, row_changes))

        {event, session}
      end)

    case result do
      {:ok, {event, session}} ->
        {:ok,
         %{
           state
           | session: session,
             seq: event.sequence,
             projection: Projection.apply_event(state.projection, normalize(event))
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The projection folds string-keyed payloads (what a JSONB round-trip
  # yields), so freshly-appended events are normalized the same way.
  defp normalize(%SessionEvent{} = event) do
    %{
      type: event.type,
      payload: Map.new(event.payload, fn {k, v} -> {to_string(k), v} end),
      game_time_ms: event.game_time_ms
    }
  end

  # ── Clock ─────────────────────────────────────────────────────────────

  defp current_game_time(%Session{status: :live, clock_started_at: %DateTime{} = started} = s) do
    s.game_time_ms + DateTime.diff(now(), started, :millisecond)
  end

  defp current_game_time(%Session{game_time_ms: accumulated}), do: accumulated

  defp now, do: DateTime.utc_now()

  # ── Snapshot & broadcast ──────────────────────────────────────────────

  defp build_snapshot(state) do
    %{
      session_id: state.session.id,
      status: state.projection.status,
      sim: state.projection.sim,
      globals: Projection.globals(state.projection),
      triggered: state.projection.triggered,
      triggered_at: state.projection.triggered_at,
      sims_before: state.projection.sims_before,
      decisions: state.projection.decisions,
      tallies: state.projection.tallies,
      vote_tallies: state.projection.vote_tallies,
      value_changes: state.projection.value_changes,
      global_changes: state.projection.global_changes,
      ending_id: state.projection.ending_id,
      game_time_ms: current_game_time(state.session),
      definition: state.definition
    }
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      Scenex.PubSub,
      Scenex.Play.session_topic(state.session.id),
      {:session_updated, state.session.id}
    )
  end
end
