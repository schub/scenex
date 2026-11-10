defmodule Scenex.Play.MetricsTest do
  # async: false — session processes access the DB (shared sandbox), and the
  # client and session counts are global.
  use Scenex.DataCase, async: false

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.{Authoring, Play}
  alias Scenex.PromEx.ScenexPlugin

  @events [
    [:scenex, :play, :command],
    [:scenex, :play, :event],
    [:scenex, :play, :session, :replayed],
    [:scenex, :play, :running_sessions],
    [:scenex, :play, :connected_clients],
    [:scenex, :platform, :users],
    [:scenex, :platform, :scenarios],
    [:scenex, :platform, :sessions],
    [:scenex, :platform, :session_events],
    [:scenex, :platform, :invitations],
    [:scenex, :platform, :media]
  ]

  def forward(event, measurements, metadata, pid),
    do: send(pid, {:telemetry, event, measurements, metadata})

  setup do
    user = user_fixture()
    scenario = scenario_fixture(user)
    gov = group_fixture(scenario, key: "Gov")
    group_fixture(scenario, key: "Media")
    event = timeline_element_fixture(scenario, key: "Blackout", position: 1)

    {:ok, crack} =
      Authoring.create_decision_option(event, gov, %{key: "Crack", name: %{"en" => "Crack"}})

    {:ok, talk} =
      Authoring.create_decision_option(event, gov, %{key: "Talk", name: %{"en" => "Talk"}})

    {:ok, session} = Play.create_session(user, scenario, %{label: "Metrics night"})
    on_exit(fn -> Play.stop_running(session.id) end)

    handler = "metrics-test-#{System.unique_integer()}"
    :telemetry.attach_many(handler, @events, &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    %{session: session, event: event, gov: gov, crack: crack, talk: talk}
  end

  describe "session telemetry" do
    test "a command reports its duration and result, its event the type", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)

      assert_receive {:telemetry, [:scenex, :play, :event], %{count: 1},
                      %{type: "session_started", correction: false}}

      assert_receive {:telemetry, [:scenex, :play, :command], %{duration: duration},
                      %{command: :start, result: :ok, reason: nil}}

      assert is_integer(duration) and duration >= 0
    end

    test "a rejected command reports its reason and appends nothing", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)
      assert {:error, :already_started} = Play.start_session(ctx.session.id)

      assert_receive {:telemetry, [:scenex, :play, :command], _,
                      %{command: :start, result: :error, reason: :already_started}}

      assert_receive {:telemetry, [:scenex, :play, :event], _, %{type: "session_started"}}
      refute_receive {:telemetry, [:scenex, :play, :event], _, %{type: "session_started"}}
    end

    test "overwriting a decision is a correction; the first decision is not", ctx do
      %{session: session, event: event, gov: gov} = ctx
      {:ok, _} = Play.start_session(session.id)
      {:ok, _} = Play.trigger_element(session.id, event.id)

      {:ok, _} = Play.choose_option(session.id, event.id, gov.id, ctx.crack.id)

      assert_receive {:telemetry, [:scenex, :play, :event], _,
                      %{type: "option_chosen", correction: false}}

      {:ok, _} = Play.choose_option(session.id, event.id, gov.id, ctx.talk.id)

      assert_receive {:telemetry, [:scenex, :play, :event], _,
                      %{type: "option_chosen", correction: true}}
    end

    test "a restarted session reports the replayed log", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)
      {:ok, _} = Play.trigger_element(ctx.session.id, ctx.event.id)
      :ok = Play.stop_running(ctx.session.id)

      {:ok, _pid} = Play.ensure_running(ctx.session.id)

      assert_receive {:telemetry, [:scenex, :play, :session, :replayed], %{events: 2}, _}
    end
  end

  describe "connected clients" do
    test "count while the tracking process lives" do
      before = Play.count_clients(:display)
      parent = self()

      client =
        spawn(fn ->
          Play.track_client(Ecto.UUID.generate(), :display)
          send(parent, :tracked)
          receive do: (:stop -> :ok)
        end)

      assert_receive :tracked
      assert Play.count_clients(:display) == before + 1

      ref = Process.monitor(client)
      send(client, :stop)
      assert_receive {:DOWN, ^ref, :process, ^client, :normal}

      wait_until(fn -> Play.count_clients(:display) == before end)
    end
  end

  describe "polled measurements" do
    test "live: running sessions and clients for every role", ctx do
      {:ok, _} = Play.ensure_running(ctx.session.id)
      ScenexPlugin.measure_live()

      assert_receive {:telemetry, [:scenex, :play, :running_sessions], %{count: running}, _}
      assert running >= 1

      for role <- Play.client_roles() do
        assert_receive {:telemetry, [:scenex, :play, :connected_clients], %{count: _},
                        %{role: ^role}}
      end
    end

    test "platform: counts from the database, zeros included" do
      ScenexPlugin.measure_platform()

      assert_receive {:telemetry, [:scenex, :platform, :sessions], %{count: 1}, %{status: :draft}}

      assert_receive {:telemetry, [:scenex, :platform, :sessions], %{count: 0}, %{status: :live}}

      assert_receive {:telemetry, [:scenex, :platform, :users], %{count: users}, _}
      assert users >= 0

      assert_receive {:telemetry, [:scenex, :platform, :scenarios], %{count: 1},
                      %{visibility: :draft}}

      assert_receive {:telemetry, [:scenex, :platform, :session_events], %{count: 0}, _}
      assert_receive {:telemetry, [:scenex, :platform, :invitations], %{pending: 0}, _}
      assert_receive {:telemetry, [:scenex, :platform, :media], %{files: 0, bytes: 0}, _}
    end
  end

  defp wait_until(fun, retries \\ 100) do
    cond do
      fun.() -> :ok
      retries == 0 -> flunk("condition not met in time")
      true -> Process.sleep(5) && wait_until(fun, retries - 1)
    end
  end
end
