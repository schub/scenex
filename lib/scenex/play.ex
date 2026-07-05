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
  alias Scenex.Authoring.{Group, Scenario}
  alias Scenex.Engine.{Condition, Sim}
  alias Scenex.Play.{CapabilityToken, Session, SessionEvent, SessionServer}
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

  @doc """
  Record a hand-count well-being tally for a `per_participant` value:
  `%{score => count}`. The latest tally sets the value's global (its
  count-weighted mean); history stays in the log and the snapshot's `tallies`.
  """
  def record_tally(session_id, value_id, counts),
    do: command(session_id, {:record_tally, value_id, counts})

  defp command(session_id, command) do
    with {:ok, _pid} <- ensure_running(session_id) do
      SessionServer.command(session_id, command)
    end
  end

  # ── Capability tokens (QR access) ─────────────────────────────────────

  @doc "Write access for exactly one group in exactly one session."
  def create_group_token(%Session{} = session, %Group{} = group) do
    %CapabilityToken{}
    |> CapabilityToken.changeset(%{
      session_id: session.id,
      kind: :group,
      group_id: group.id,
      token: CapabilityToken.generate()
    })
    |> Repo.insert()
  end

  @doc "Read-only access for the projected board."
  def create_display_token(%Session{} = session) do
    %CapabilityToken{}
    |> CapabilityToken.changeset(%{
      session_id: session.id,
      kind: :display,
      token: CapabilityToken.generate()
    })
    |> Repo.insert()
  end

  def list_tokens(%Session{} = session) do
    Repo.all(
      from t in CapabilityToken,
        where: t.session_id == ^session.id,
        order_by: t.inserted_at,
        preload: [:group]
    )
  end

  def delete_token(%CapabilityToken{} = token), do: Repo.delete(token)

  @doc "Resolve a token string to `{:ok, token_with_session}` or `:error`."
  def fetch_token(token_string) when is_binary(token_string) do
    token =
      Repo.one(
        from t in CapabilityToken,
          where: t.token == ^token_string,
          preload: [:session, :group]
      )

    cond do
      is_nil(token) -> :error
      expired?(token) -> :error
      true -> {:ok, token}
    end
  end

  def fetch_token(_), do: :error

  defp expired?(%CapabilityToken{expires_at: nil}), do: false

  defp expired?(%CapabilityToken{expires_at: at}),
    do: DateTime.compare(at, DateTime.utc_now()) == :lt

  @doc """
  Whether a triggered element's decisions are all in: elections need a
  declared winner, sidequests an adjudicated outcome, events one decision per
  group that has options. Corrections stay possible (last wins) — "decided"
  is a presentation state, not a lock.
  """
  def element_decided?(snapshot, %{kind: :election, id: id}),
    do: get_in(snapshot.decisions, [id, :winner]) != nil

  def element_decided?(snapshot, %{kind: :sidequest, id: id}),
    do: get_in(snapshot.decisions, [id, :outcome]) != nil

  def element_decided?(snapshot, %{kind: :event, id: id}) do
    group_ids =
      snapshot.definition.options_by_element[id]
      |> List.wrap()
      |> Enum.map(& &1.group_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    group_ids != [] and Enum.all?(group_ids, &get_in(snapshot.decisions, [id, &1]))
  end

  # ── Gates (player-side) ───────────────────────────────────────────────

  @doc """
  Whether an option's gate is open, evaluated against the board **before its
  element** (same semantics as the dry-run). Fail-open on unevaluable
  conditions. The GM console does not enforce gates (the GM disposes);
  player-facing views must.
  """
  def gate_open?(_snapshot, _element_id, %{condition: nil}), do: true

  def gate_open?(snapshot, element_id, option) do
    sim = snapshot.sims_before[element_id] || snapshot.sim
    globals = Sim.globals(sim)

    global_ctx =
      Map.new(
        for vd <- snapshot.definition.value_dimensions, is_number(globals[vd.id]) do
          {vd.key, globals[vd.id]}
        end
      )

    context =
      case option.group_id do
        nil ->
          %{global: global_ctx}

        group_id ->
          self_ctx =
            Map.new(
              for vd <- snapshot.definition.value_dimensions,
                  is_number(Sim.get(sim, vd.id, group_id)) do
                {vd.key, Sim.get(sim, vd.id, group_id)}
              end
            )

          %{global: global_ctx, self: self_ctx}
      end

    case Condition.evaluate(option.condition, context) do
      {:ok, result} -> result
      {:error, _} -> true
    end
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  def session_topic(session_id), do: "play:session:#{session_id}"

  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(Scenex.PubSub, session_topic(session_id))
  end
end
