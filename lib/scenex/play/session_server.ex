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
    definition = Definition.load(Authoring.get_scenario!(session.scenario_id))

    events =
      Repo.all(from e in SessionEvent, where: e.session_id == ^session_id, order_by: e.sequence)

    projection = Enum.reduce(events, Projection.new(definition), &Projection.apply_event(&2, &1))
    sequence = events |> List.last() |> then(&((&1 && &1.sequence) || 0))

    {:ok, %{session: session, definition: definition, projection: projection, seq: sequence}}
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
            broadcast(state)
            {:reply, {:ok, build_snapshot(state)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
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
      payload: Map.new(event.payload, fn {k, v} -> {to_string(k), v} end)
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
      decisions: state.projection.decisions,
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
