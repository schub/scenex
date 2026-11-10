defmodule Scenex.PromEx.ScenexPlugin do
  @moduledoc """
  Scenex's own metrics, on top of the generic PromEx plugins.

  **Play activity** — from the `:telemetry` events `Scenex.Play.SessionServer`
  emits:

    * `scenex_play_events_total{type, correction}` — appended session events.
      `type` covers beats (`element_triggered`), decisions, deadlines,
      sessions started/ended; `correction` marks a GM overwriting a decision.
    * `scenex_play_command_duration_milliseconds{command, result}` — GM and
      player commands, end to end including the database write.
    * `scenex_play_commands_rejected_total{command, reason}`.
    * `scenex_play_replay_duration_milliseconds` and
      `scenex_play_replay_events` — session process (re)starts.

  **Live shows** — polled every 5 seconds:

    * `scenex_play_running_sessions` — session processes in memory.
    * `scenex_play_connected_clients{role}` — connected GM consoles, group
      screens and displays.

  **Platform** — polled from the database every 30 seconds:

    * `scenex_platform_users{confirmed}`, `scenex_platform_scenarios{visibility}`,
      `scenex_platform_sessions{status}`, `scenex_platform_session_events`,
      `scenex_platform_invitations_pending`, `scenex_platform_media_files`,
      `scenex_platform_media_bytes`.

  Measurement functions never raise: `:telemetry_poller` drops a measurement
  for good once it fails, and a database hiccup must not end the metric.
  """
  use PromEx.Plugin

  import Ecto.Query

  require Logger

  alias Scenex.Accounts.User
  alias Scenex.Authoring.{Scenario, ScenarioInvitation}
  alias Scenex.Media.MediaFile
  alias Scenex.Play
  alias Scenex.Play.{Session, SessionEvent}
  alias Scenex.Repo

  @duration_buckets [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000]
  @size_buckets [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

  @impl true
  def event_metrics(_opts) do
    Event.build(:scenex_play_event_metrics, [
      counter([:scenex, :play, :events, :total],
        event_name: [:scenex, :play, :event],
        description: "Session events appended to the log.",
        tags: [:type, :correction]
      ),
      distribution([:scenex, :play, :command, :duration, :milliseconds],
        event_name: [:scenex, :play, :command],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Time to validate, persist and broadcast a session command.",
        tags: [:command, :result],
        reporter_options: [buckets: @duration_buckets]
      ),
      counter([:scenex, :play, :commands, :rejected, :total],
        event_name: [:scenex, :play, :command],
        description: "Session commands rejected by validation or persistence.",
        keep: &(&1.result == :error),
        tags: [:command, :reason],
        tag_values: &%{command: &1.command, reason: reason_label(&1.reason)}
      ),
      distribution([:scenex, :play, :replay, :duration, :milliseconds],
        event_name: [:scenex, :play, :session, :replayed],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Time to start a session process and replay its log.",
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution([:scenex, :play, :replay, :events],
        event_name: [:scenex, :play, :session, :replayed],
        measurement: :events,
        description: "Log length replayed when a session process starts.",
        reporter_options: [buckets: @size_buckets]
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    [
      Polling.build(
        :scenex_live_polling_metrics,
        Keyword.get(opts, :live_poll_rate, 5_000),
        {__MODULE__, :measure_live, []},
        [
          last_value([:scenex, :play, :running_sessions],
            event_name: [:scenex, :play, :running_sessions],
            measurement: :count,
            description: "Session processes running in memory."
          ),
          last_value([:scenex, :play, :connected_clients],
            event_name: [:scenex, :play, :connected_clients],
            measurement: :count,
            description: "Connected live clients by role (gm, group, display).",
            tags: [:role]
          )
        ]
      ),
      Polling.build(
        :scenex_platform_polling_metrics,
        Keyword.get(opts, :platform_poll_rate, 30_000),
        {__MODULE__, :measure_platform, []},
        [
          last_value([:scenex, :platform, :users],
            event_name: [:scenex, :platform, :users],
            measurement: :count,
            description: "User accounts.",
            tags: [:confirmed]
          ),
          last_value([:scenex, :platform, :scenarios],
            event_name: [:scenex, :platform, :scenarios],
            measurement: :count,
            description: "Scenarios by visibility.",
            tags: [:visibility]
          ),
          last_value([:scenex, :platform, :sessions],
            event_name: [:scenex, :platform, :sessions],
            measurement: :count,
            description: "Sessions by status.",
            tags: [:status]
          ),
          last_value([:scenex, :platform, :session_events],
            event_name: [:scenex, :platform, :session_events],
            measurement: :count,
            description: "Session events stored, all sessions."
          ),
          last_value([:scenex, :platform, :invitations, :pending],
            event_name: [:scenex, :platform, :invitations],
            measurement: :pending,
            description: "Invitations sent and not yet accepted or expired."
          ),
          last_value([:scenex, :platform, :media, :files],
            event_name: [:scenex, :platform, :media],
            measurement: :files,
            description: "Uploaded media files."
          ),
          last_value([:scenex, :platform, :media, :bytes],
            event_name: [:scenex, :platform, :media],
            measurement: :bytes,
            description: "Total size of uploaded media, in bytes."
          )
        ]
      )
    ]
  end

  @doc false
  def measure_live do
    safely(:live, Scenex.Play.SessionSupervisor, fn ->
      emit([:running_sessions], %{count: Play.count_running_sessions()}, %{}, :play)

      for role <- Play.client_roles() do
        emit([:connected_clients], %{count: Play.count_clients(role)}, %{role: role}, :play)
      end
    end)
  end

  @doc false
  def measure_platform do
    safely(:platform, Repo, fn ->
      users =
        from(u in User,
          group_by: not is_nil(u.confirmed_at),
          select: {not is_nil(u.confirmed_at), count(u.id)}
        )
        |> Repo.all()
        |> Map.new()

      for confirmed <- [true, false] do
        emit([:users], %{count: Map.get(users, confirmed, 0)}, %{confirmed: confirmed})
      end

      scenarios = count_by(Scenario, :visibility)

      for visibility <- Scenario.visibilities() do
        emit([:scenarios], %{count: Map.get(scenarios, visibility, 0)}, %{visibility: visibility})
      end

      sessions = count_by(Session, :status)

      for status <- Session.statuses() do
        emit([:sessions], %{count: Map.get(sessions, status, 0)}, %{status: status})
      end

      emit([:session_events], %{count: Repo.aggregate(SessionEvent, :count)}, %{})

      pending =
        Repo.aggregate(
          from(i in ScenarioInvitation,
            where: i.inserted_at > ago(^ScenarioInvitation.validity_in_days(), "day")
          ),
          :count
        )

      emit([:invitations], %{pending: pending}, %{})

      {files, bytes} =
        Repo.one(
          from m in MediaFile, select: {count(m.id), type(coalesce(sum(m.size), 0), :integer)}
        )

      emit([:media], %{files: files, bytes: bytes}, %{})
    end)
  end

  defp count_by(schema, field) do
    from(r in schema, group_by: field(r, ^field), select: {field(r, ^field), count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp emit(name, measurements, metadata, area \\ :platform),
    do: :telemetry.execute([:scenex, area | name], measurements, metadata)

  # PromEx starts before the processes it measures and polls right away.
  defp safely(group, needed_process, fun) do
    if Process.whereis(needed_process), do: fun.()
    :ok
  rescue
    error ->
      Logger.warning("metrics: #{group} measurement failed: #{Exception.message(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.warning("metrics: #{group} measurement exited: #{inspect(reason)}")
      :ok
  end

  defp reason_label(nil), do: "none"
  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(_reason), do: "other"
end
