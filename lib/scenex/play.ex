defmodule Scenex.Play do
  @moduledoc """
  The Play context (Layer 3) — running live sessions of a scenario.

  Sessions are **event-sourced**: an append-only `SessionEvent` log is the
  source of truth; the current board is a projection folded by one
  `SessionServer` process per running session (isolated, concurrent,
  crash-recovered by replay). This context creates/lists sessions and fronts
  the command API; the server does the work.
  """

  import Ecto.Query, warn: false

  alias Scenex.Accounts.User
  alias Scenex.Authoring.Scenario
  alias Scenex.Play.{Session, SessionEvent, SessionServer}
  alias Scenex.Repo

  # ── Sessions (rows) ───────────────────────────────────────────────────

  def list_sessions(%Scenario{} = scenario) do
    Repo.all(
      from s in Session, where: s.scenario_id == ^scenario.id, order_by: [desc: s.inserted_at]
    )
  end

  def get_session!(id), do: Repo.get!(Session, id)

  @doc "Create a session (status `:draft`); the creator acts as its GM."
  def create_session(%User{} = user, %Scenario{} = scenario, attrs) do
    %Session{}
    |> Session.changeset(
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{"scenario_id" => scenario.id, "created_by_id" => user.id})
    )
    |> Repo.insert()
  end

  def change_session(%Session{} = session, attrs \\ %{}), do: Session.changeset(session, attrs)

  @doc "The full event log, oldest first."
  def list_session_events(%Session{} = session) do
    Repo.all(from e in SessionEvent, where: e.session_id == ^session.id, order_by: e.sequence)
  end

  # ── Runtime ───────────────────────────────────────────────────────────

  @doc "Start (or find) the session's process; replays the log on cold start."
  def ensure_running(session_id) do
    case DynamicSupervisor.start_child(Scenex.Play.SessionSupervisor, {SessionServer, session_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop the session's process (the log persists; restart replays)."
  def stop_running(session_id) do
    case SessionServer.whereis(session_id) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  def snapshot(session_id) do
    with {:ok, _pid} <- ensure_running(session_id), do: SessionServer.snapshot(session_id)
  end

  # ── Commands (validated and appended by the session process) ─────────

  def start_session(session_id), do: command(session_id, {:start})
  def pause_session(session_id), do: command(session_id, {:pause})
  def resume_session(session_id), do: command(session_id, {:resume})
  def end_session(session_id), do: command(session_id, {:end_session})
  def select_ending(session_id, ending_id), do: command(session_id, {:select_ending, ending_id})

  def trigger_element(session_id, element_id),
    do: command(session_id, {:trigger_element, element_id})

  @doc "A group's decision on a triggered event element (last entry wins)."
  def choose_option(session_id, element_id, group_id, option_id),
    do: command(session_id, {:choose_option, element_id, group_id, option_id})

  @doc "Resolve an election: the winning option, plus the (hand-count) tally."
  def resolve_election(session_id, element_id, option_id, tally \\ %{}),
    do: command(session_id, {:resolve_election, element_id, option_id, tally})

  @doc "GM adjudication: which outcome bundle (success/failure) applies."
  def adjudicate_sidequest(session_id, element_id, option_id),
    do: command(session_id, {:adjudicate_sidequest, element_id, option_id})

  defp command(session_id, command) do
    with {:ok, _pid} <- ensure_running(session_id) do
      SessionServer.command(session_id, command)
    end
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  def session_topic(session_id), do: "play:session:#{session_id}"

  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(Scenex.PubSub, session_topic(session_id))
  end
end
