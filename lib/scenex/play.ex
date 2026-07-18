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
  alias Scenex.Authoring
  alias Scenex.Authoring.{Group, Scenario}
  alias Scenex.Engine.{Condition, Sim}
  alias Scenex.Play.{CapabilityToken, Session, SessionEvent, SessionGroup, SessionServer}
  alias Scenex.Repo

  # ── Sessions (rows) ───────────────────────────────────────────────────

  def list_sessions(%Scenario{} = scenario) do
    Repo.all(
      from s in Session,
        where: s.scenario_id == ^scenario.id,
        order_by: [desc: s.inserted_at],
        preload: [:created_by]
    )
  end

  def get_session!(id), do: Repo.get!(Session, id)

  @doc """
  Whether a user may run this session (open the console, send commands).

  A session belongs to the author who created it — other authors of the same
  scenario cannot control it. The scenario owner keeps an override as the
  recovery path for live events (GM unavailable, orphaned sessions).
  """
  def gm?(%Session{} = session, %User{} = user, role) do
    role == :owner or (role == :author and session.created_by_id == user.id)
  end

  @doc """
  Create a session (status `:draft`); the creator acts as its GM.

  `attrs` may carry `group_ids` — the subset of the scenario's group pool
  playing in this show (minimum two, venues seat different head counts).
  Without it the session plays with all groups. The selection is fixed at
  creation: the event log replays against it, so it must never change.
  """
  def create_session(%User{} = user, %Scenario{} = scenario, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    {group_ids, attrs} = Map.pop(attrs, "group_ids")

    changeset =
      Session.changeset(
        %Session{},
        Map.merge(attrs, %{"scenario_id" => scenario.id, "created_by_id" => user.id})
      )

    case selected_groups(scenario, group_ids) do
      :all ->
        Repo.insert(changeset)

      {:ok, groups} ->
        changeset |> Ecto.Changeset.put_assoc(:groups, groups) |> Repo.insert()

      {:error, message} ->
        {:error,
         changeset |> Ecto.Changeset.add_error(:groups, message) |> Map.put(:action, :insert)}
    end
  end

  defp selected_groups(_scenario, nil), do: :all

  defp selected_groups(scenario, group_ids) when is_list(group_ids) do
    pool = Map.new(Authoring.list_groups(scenario), &{&1.id, &1})
    ids = Enum.uniq(group_ids)

    cond do
      not Enum.all?(ids, &Map.has_key?(pool, &1)) -> {:error, "must belong to this scenario"}
      length(ids) < 2 -> {:error, "select at least two groups"}
      true -> {:ok, Enum.map(ids, &pool[&1])}
    end
  end

  @doc """
  The ids of the groups playing in this session, or `nil` when the session
  plays with the scenario's full pool (no selection recorded).
  """
  def session_group_ids(%Session{} = session) do
    case Repo.all(
           from sg in SessionGroup, where: sg.session_id == ^session.id, select: sg.group_id
         ) do
      [] -> nil
      ids -> ids
    end
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
    ids = session_group_ids(session)

    if is_list(ids) and group.id not in ids do
      {:error, :group_not_in_session}
    else
      %CapabilityToken{}
      |> CapabilityToken.changeset(%{
        session_id: session.id,
        kind: :group,
        group_id: group.id,
        token: CapabilityToken.generate()
      })
      |> Repo.insert()
    end
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

  @doc """
  The still-fresh delta for a board cell (or, with `group_id` nil, a global),
  or nil once the scenario's highlight window has passed. Freshness runs on
  the game clock, so pausing keeps a fresh change visible.
  """
  def recent_delta(snapshot, value_id, group_id \\ nil) do
    change =
      case group_id do
        nil -> snapshot.global_changes[value_id]
        group_id -> snapshot.value_changes[{value_id, group_id}]
      end

    with {delta, at} <- change,
         true <- snapshot.game_time_ms - at <= snapshot.definition.change_highlight_ms do
      delta
    else
      _ -> nil
    end
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
