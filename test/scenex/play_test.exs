defmodule Scenex.PlayTest do
  # async: false — session processes access the DB, so the sandbox runs in
  # shared mode (see DataCase: shared when not async).
  use Scenex.DataCase, async: false

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.{Authoring, Play}
  alias Scenex.Engine.Sim

  # A compact scenario exercising all three kinds + an ending:
  # 1 value (stability, avg, 0..10), 2 groups at 5.0,
  # event (two options for gov), election (matrix), sidequest (success bundle),
  # one conditional + one fallback ending.
  defp definition_fixture(user) do
    scenario = scenario_fixture(user)

    stability =
      value_dimension_fixture(scenario,
        key: "stability",
        name: %{"en" => "Stability"},
        min: 0.0,
        max: 10.0
      )

    gov = group_fixture(scenario, handle: "Gov")
    media = group_fixture(scenario, handle: "Media")
    Authoring.set_group_initial_value(gov, stability, 5.0)
    Authoring.set_group_initial_value(media, stability, 5.0)

    event = timeline_element_fixture(scenario, handle: "Blackout", position: 1)

    {:ok, crack} =
      Authoring.create_decision_option(event, gov, %{handle: "Crack", text: %{"en" => "Crack"}})

    Authoring.set_option_effect(crack, stability, 2.0)

    {:ok, talk} =
      Authoring.create_decision_option(event, gov, %{handle: "Talk", text: %{"en" => "Talk"}})

    Authoring.set_option_effect(talk, stability, -1.0)

    {:ok, election} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Referendum",
        title: %{"en" => "Referendum"},
        kind: :election,
        position: 2
      })

    {:ok, yes} =
      Authoring.create_decision_option(election, nil, %{handle: "Yes", text: %{"en" => "Yes"}})

    Authoring.set_option_effect(yes, stability, gov, 3.0)
    Authoring.set_option_effect(yes, stability, media, -2.0)

    {:ok, sidequest} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Leak",
        title: %{"en" => "Leak"},
        kind: :sidequest,
        position: 3
      })

    {:ok, success} =
      Authoring.create_decision_option(sidequest, nil, %{
        handle: "Published",
        text: %{"en" => "Published"},
        outcome: :success
      })

    Authoring.set_option_effect(success, stability, media, 1.0)

    {:ok, stable_end} =
      Authoring.create_ending(scenario, %{
        handle: "Stabilized",
        title: %{"en" => "Stabilized"},
        condition: "global(stability) >= 6"
      })

    %{
      scenario: scenario,
      stability: stability,
      gov: gov,
      media: media,
      event: event,
      crack: crack,
      talk: talk,
      election: election,
      yes: yes,
      sidequest: sidequest,
      success: success,
      stable_end: stable_end
    }
  end

  setup do
    user = user_fixture()
    fixtures = definition_fixture(user)

    {:ok, session} = Play.create_session(user, fixtures.scenario, %{label: "Test night"})
    on_exit(fn -> Play.stop_running(session.id) end)

    Map.merge(fixtures, %{user: user, session: session})
  end

  defp stab(snapshot, %{stability: vd}, group), do: Sim.get(snapshot.sim, vd.id, group.id)

  defp wait_until(fun, retries \\ 100) do
    cond do
      fun.() -> :ok
      retries == 0 -> flunk("condition not met in time")
      true -> Process.sleep(5) && wait_until(fun, retries - 1)
    end
  end

  test "a full session: events, election, sidequest, ending", ctx do
    %{session: session} = ctx

    assert {:ok, snap} = Play.start_session(session.id)
    assert snap.status == :live

    # Event: gov cracks down -> stability 7
    assert {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    assert {:ok, snap} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)
    assert stab(snap, ctx, ctx.gov) == 7.0

    # Correction by re-entry (last wins): gov actually talked -> stability 4
    assert {:ok, snap} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.talk.id)
    assert stab(snap, ctx, ctx.gov) == 4.0

    # Election: Yes wins -> matrix (gov +3 = 7, media -2 = 3)
    assert {:ok, _} = Play.trigger_element(session.id, ctx.election.id)

    assert {:ok, snap} =
             Play.resolve_election(session.id, ctx.election.id, ctx.yes.id, %{ctx.yes.id => 21})

    assert stab(snap, ctx, ctx.gov) == 7.0
    assert stab(snap, ctx, ctx.media) == 3.0

    # Sidequest success -> media +1 = 4
    assert {:ok, _} = Play.trigger_element(session.id, ctx.sidequest.id)
    assert {:ok, snap} = Play.adjudicate_sidequest(session.id, ctx.sidequest.id, ctx.success.id)
    assert stab(snap, ctx, ctx.media) == 4.0

    # End and pick the ending (global avg (7+4)/2 = 5.5 -> Stabilized not met,
    # but the GM may override — conditions are recommendations).
    assert {:ok, snap} = Play.end_session(session.id)
    assert snap.status == :ended
    assert {:ok, snap} = Play.select_ending(session.id, ctx.stable_end.id)
    assert snap.ending_id == ctx.stable_end.id
    assert Play.get_session!(session.id).ending_id == ctx.stable_end.id

    # The log recorded everything, in order.
    types = session |> Play.list_session_events() |> Enum.map(& &1.type)

    assert types == [
             "session_started",
             "element_triggered",
             "option_chosen",
             "option_chosen",
             "element_triggered",
             "election_resolved",
             "element_triggered",
             "sidequest_adjudicated",
             "session_ended",
             "ending_selected"
           ]
  end

  test "a session survives a process restart (replay)", ctx do
    %{session: session} = ctx

    {:ok, _} = Play.start_session(session.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    {:ok, _} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.election.id)
    {:ok, before} = Play.resolve_election(session.id, ctx.election.id, ctx.yes.id)

    :ok = Play.stop_running(session.id)
    # Registry unregistration is asynchronous; wait for the name to free.
    wait_until(fn -> Scenex.Play.SessionServer.whereis(session.id) == nil end)

    after_restart = Play.snapshot(session.id)

    assert after_restart.status == before.status
    assert after_restart.triggered == before.triggered
    assert after_restart.decisions == before.decisions
    assert after_restart.sim.group_values == before.sim.group_values
  end

  test "two sessions of the same scenario are isolated", ctx do
    %{session: session_a, user: user, scenario: scenario} = ctx
    {:ok, session_b} = Play.create_session(user, scenario, %{label: "Other night"})
    on_exit(fn -> Play.stop_running(session_b.id) end)

    {:ok, _} = Play.start_session(session_a.id)
    {:ok, _} = Play.start_session(session_b.id)
    {:ok, _} = Play.trigger_element(session_a.id, ctx.event.id)
    {:ok, snap_a} = Play.choose_option(session_a.id, ctx.event.id, ctx.gov.id, ctx.crack.id)

    snap_b = Play.snapshot(session_b.id)

    assert stab(snap_a, ctx, ctx.gov) == 7.0
    assert stab(snap_b, ctx, ctx.gov) == 5.0
    assert snap_b.triggered == []
  end

  test "the game clock pauses and resumes", ctx do
    %{session: session} = ctx

    {:ok, _} = Play.start_session(session.id)
    Process.sleep(15)
    {:ok, paused} = Play.pause_session(session.id)
    assert paused.status == :paused
    assert paused.game_time_ms >= 15

    # Frozen while paused.
    Process.sleep(15)
    frozen = Play.snapshot(session.id)
    assert frozen.game_time_ms == paused.game_time_ms

    {:ok, _} = Play.resume_session(session.id)
    Process.sleep(15)
    resumed = Play.snapshot(session.id)
    assert resumed.game_time_ms >= paused.game_time_ms + 15
  end

  test "commands are validated against the projection", ctx do
    %{session: session} = ctx

    # Nothing runs before start.
    assert {:error, :not_running} = Play.trigger_element(session.id, ctx.event.id)

    {:ok, _} = Play.start_session(session.id)
    assert {:error, :already_started} = Play.start_session(session.id)

    # Decisions need a triggered element.
    assert {:error, :not_triggered} =
             Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)

    {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    assert {:error, :already_triggered} = Play.trigger_element(session.id, ctx.event.id)

    # Kind and ownership are enforced.
    assert {:error, {:wrong_kind, :event}} =
             Play.resolve_election(session.id, ctx.event.id, ctx.crack.id)

    assert {:error, :option_not_for_group} =
             Play.choose_option(session.id, ctx.event.id, ctx.media.id, ctx.crack.id)

    assert {:error, :unknown_option} =
             Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.yes.id)

    # Endings only after the end, and only known ones.
    assert {:error, :not_ended} = Play.select_ending(session.id, ctx.stable_end.id)
    {:ok, _} = Play.end_session(session.id)
    assert {:error, :unknown_ending} = Play.select_ending(session.id, ctx.crack.id)
  end

  test "session updates are broadcast", ctx do
    %{session: session} = ctx
    Play.subscribe(session.id)

    {:ok, _} = Play.start_session(session.id)

    session_id = session.id
    assert_receive {:session_updated, ^session_id}
  end
end
