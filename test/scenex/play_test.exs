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

    wellbeing =
      value_dimension_fixture(scenario,
        key: "wellbeing",
        name: %{"en" => "Well-being"},
        input_scope: :per_participant,
        min: 1.0,
        max: 4.0
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
      wellbeing: wellbeing,
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
    assert snap.vote_tallies[ctx.election.id] == %{ctx.yes.id => 21}

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

  test "well-being tallies feed the per-participant global (latest wins)", ctx do
    %{session: session, wellbeing: wellbeing} = ctx

    {:ok, snap} = Play.start_session(session.id)
    assert snap.globals[wellbeing.id] == nil

    # Counts arrive stringly from the form; scores fold back to numbers.
    {:ok, snap} = Play.record_tally(session.id, wellbeing.id, %{"4" => 2, "3" => 1, "1" => 1})
    assert snap.globals[wellbeing.id] == 3.0
    assert [%{counts: %{4 => 2, 3 => 1, 1 => 1}}] = snap.tallies[wellbeing.id]

    # A later reading supersedes the global; history keeps both.
    {:ok, snap} = Play.record_tally(session.id, wellbeing.id, %{"2" => 3, "1" => 1})
    assert snap.globals[wellbeing.id] == 1.75
    assert length(snap.tallies[wellbeing.id]) == 2

    types = session |> Play.list_session_events() |> Enum.map(& &1.type)
    assert Enum.count(types, &(&1 == "tally_recorded")) == 2
  end

  test "tally commands are validated", ctx do
    %{session: session, wellbeing: wellbeing, stability: stability} = ctx

    assert {:error, :not_running} =
             Play.record_tally(session.id, wellbeing.id, %{"4" => 1})

    {:ok, _} = Play.start_session(session.id)

    assert {:error, :unknown_value} = Play.record_tally(session.id, ctx.gov.id, %{"4" => 1})

    assert {:error, :not_per_participant} =
             Play.record_tally(session.id, stability.id, %{"4" => 1})

    assert {:error, :invalid_tally} = Play.record_tally(session.id, wellbeing.id, %{})
    assert {:error, :invalid_tally} = Play.record_tally(session.id, wellbeing.id, %{"4" => -1})
    assert {:error, :invalid_tally} = Play.record_tally(session.id, wellbeing.id, %{"x" => 1})
    assert {:error, :empty_tally} = Play.record_tally(session.id, wellbeing.id, %{"4" => 0})
  end

  test "a session survives a process restart (replay)", ctx do
    %{session: session} = ctx

    {:ok, _} = Play.start_session(session.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    {:ok, _} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.election.id)
    {:ok, _} = Play.resolve_election(session.id, ctx.election.id, ctx.yes.id)
    {:ok, before} = Play.record_tally(session.id, ctx.wellbeing.id, %{"4" => 1, "2" => 1})

    :ok = Play.stop_running(session.id)
    # Registry unregistration is asynchronous; wait for the name to free.
    wait_until(fn -> Scenex.Play.SessionServer.whereis(session.id) == nil end)

    after_restart = Play.snapshot(session.id)

    assert after_restart.status == before.status
    assert after_restart.triggered == before.triggered
    assert after_restart.decisions == before.decisions
    assert after_restart.sim.group_values == before.sim.group_values
    assert after_restart.tallies == before.tallies
    assert after_restart.globals == before.globals
    assert after_restart.value_changes == before.value_changes
    assert after_restart.global_changes == before.global_changes
  end

  test "board changes are tracked per cell with game-time stamps (latest wins)", ctx do
    %{session: session} = ctx

    {:ok, _} = Play.start_session(session.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    {:ok, snap} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)

    # Crack: gov stability 5 -> 7, global avg 5 -> 6; media untouched.
    assert {2.0, _at} = snap.value_changes[{ctx.stability.id, ctx.gov.id}]
    assert Play.recent_delta(snap, ctx.stability.id, ctx.gov.id) == 2.0
    assert Play.recent_delta(snap, ctx.stability.id) == 1.0
    assert Play.recent_delta(snap, ctx.stability.id, ctx.media.id) == nil

    # Correction: Talk replaces Crack (gov 7 -> 4); only the latest change shows.
    {:ok, snap} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.talk.id)
    assert Play.recent_delta(snap, ctx.stability.id, ctx.gov.id) == -3.0

    # Tallies move the per-participant global too; a first reading appears
    # out of nowhere and gets no delta.
    {:ok, snap} = Play.record_tally(session.id, ctx.wellbeing.id, %{"4" => 4})
    assert Play.recent_delta(snap, ctx.wellbeing.id) == nil

    {:ok, snap} = Play.record_tally(session.id, ctx.wellbeing.id, %{"2" => 4})
    assert Play.recent_delta(snap, ctx.wellbeing.id) == -2.0
  end

  test "change markers expire after the scenario's highlight window", ctx do
    # A 0-second window: the marker is stale as soon as the clock moves.
    {:ok, _} = Authoring.update_scenario(ctx.scenario, %{change_highlight_seconds: 0})
    {:ok, session} = Play.create_session(ctx.user, ctx.scenario, %{label: "Short window"})
    on_exit(fn -> Play.stop_running(session.id) end)

    {:ok, _} = Play.start_session(session.id)
    {:ok, _} = Play.trigger_element(session.id, ctx.event.id)
    {:ok, _} = Play.choose_option(session.id, ctx.event.id, ctx.gov.id, ctx.crack.id)

    wait_until(fn ->
      Play.recent_delta(Play.snapshot(session.id), ctx.stability.id, ctx.gov.id) == nil
    end)

    # The change itself stays recorded — only the marker faded.
    assert {2.0, _at} = Play.snapshot(session.id).value_changes[{ctx.stability.id, ctx.gov.id}]
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

  test "a lapsed deadline applies default options to undecided slots", ctx do
    %{session: session, scenario: scenario, stability: stability, gov: gov, media: media} = ctx

    # An event element with a deadline; gov and media each have a default.
    {:ok, timed} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Timed",
        title: %{"en" => "Timed"},
        position: 4,
        deadline_seconds: 3600
      })

    {:ok, gov_default} =
      Authoring.create_decision_option(timed, gov, %{
        handle: "Gov default",
        text: %{"en" => "Gov default"},
        is_default: true
      })

    Authoring.set_option_effect(gov_default, stability, -2.0)

    {:ok, _media_default} =
      Authoring.create_decision_option(timed, media, %{
        handle: "Media default",
        text: %{"en" => "Media default"},
        is_default: true
      })

    {:ok, media_active} =
      Authoring.create_decision_option(timed, media, %{
        handle: "Media active",
        text: %{"en" => "Media active"}
      })

    Authoring.set_option_effect(media_active, stability, 1.0)

    {:ok, _} = Play.start_session(session.id)
    {:ok, _} = Play.trigger_element(session.id, timed.id)

    # Media decides in time; gov does not.
    {:ok, _} = Play.choose_option(session.id, timed.id, media.id, media_active.id)

    # Fire the deadline directly (deterministic — no sleeping on real timers).
    pid = Scenex.Play.SessionServer.whereis(session.id)
    send(pid, {:deadline, timed.id})

    snap = Play.snapshot(session.id)

    # Gov got its default (5 - 2 = 3); media's real decision survived (5 + 1 = 6).
    assert stab(snap, ctx, ctx.gov) == 3.0
    assert stab(snap, ctx, ctx.media) == 6.0
    assert snap.decisions[timed.id][gov.id] == gov_default.id
    assert snap.decisions[timed.id][media.id] == media_active.id

    types = session |> Play.list_session_events() |> Enum.map(& &1.type)
    assert Enum.count(types, &(&1 == "deadline_lapsed")) == 1
  end

  test "session updates are broadcast", ctx do
    %{session: session} = ctx
    Play.subscribe(session.id)

    {:ok, _} = Play.start_session(session.id)

    session_id = session.id
    assert_receive {:session_updated, ^session_id}
  end

  describe "group selection per session" do
    test "a session runs with only its selected groups; excluded groups vanish", ctx do
      fringe = group_fixture(ctx.scenario, handle: "Fringe")
      Authoring.set_group_initial_value(fringe, ctx.stability, 5.0)
      # An event option for the excluded group and an election effect on it —
      # both must be invisible / inert in this session.
      {:ok, fringe_opt} =
        Authoring.create_decision_option(ctx.event, fringe, %{
          handle: "FringeMove",
          text: %{"en" => "Fringe move"}
        })

      Authoring.set_option_effect(ctx.yes, ctx.stability, fringe, 5.0)

      {:ok, session} =
        Play.create_session(ctx.user, ctx.scenario, %{
          label: "Small venue",
          group_ids: [ctx.gov.id, ctx.media.id]
        })

      on_exit(fn -> Play.stop_running(session.id) end)

      assert Enum.sort(Play.session_group_ids(session)) ==
               Enum.sort([ctx.gov.id, ctx.media.id])

      snap = Play.snapshot(session.id)
      assert Enum.sort(snap.definition.group_ids) == Enum.sort([ctx.gov.id, ctx.media.id])
      refute Map.has_key?(snap.definition.groups, fringe.id)

      refute Enum.any?(
               snap.definition.options_by_element[ctx.event.id],
               &(&1.id == fringe_opt.id)
             )

      {:ok, _} = Play.start_session(session.id)
      {:ok, _} = Play.trigger_element(session.id, ctx.election.id)
      {:ok, snap} = Play.resolve_election(session.id, ctx.election.id, ctx.yes.id)

      # gov 5+3=8, media 5-2=3; the +5 aimed at excluded fringe no-ops.
      assert Sim.get(snap.sim, ctx.stability.id, ctx.gov.id) == 8.0
      assert Sim.get(snap.sim, ctx.stability.id, ctx.media.id) == 3.0
      assert Sim.get(snap.sim, ctx.stability.id, fringe.id) == nil
      refute fringe.id in snap.sim.groups
    end

    test "a session without a selection plays with the full pool", ctx do
      assert Play.session_group_ids(ctx.session) == nil

      snap = Play.snapshot(ctx.session.id)
      assert Enum.sort(snap.definition.group_ids) == Enum.sort([ctx.gov.id, ctx.media.id])
    end

    test "selections need at least two groups from this scenario", ctx do
      assert {:error, changeset} =
               Play.create_session(ctx.user, ctx.scenario, %{
                 label: "Solo",
                 group_ids: [ctx.gov.id]
               })

      assert "select at least two groups" in errors_on(changeset).groups

      assert {:error, changeset} =
               Play.create_session(ctx.user, ctx.scenario, %{
                 label: "Alien",
                 group_ids: [ctx.gov.id, Ecto.UUID.generate()]
               })

      assert "must belong to this scenario" in errors_on(changeset).groups
    end

    test "group tokens are only issued for selected groups", ctx do
      fringe = group_fixture(ctx.scenario, handle: "Fringe")

      {:ok, session} =
        Play.create_session(ctx.user, ctx.scenario, %{
          label: "Small venue",
          group_ids: [ctx.gov.id, ctx.media.id]
        })

      assert {:error, :group_not_in_session} = Play.create_group_token(session, fringe)
      assert {:ok, _} = Play.create_group_token(session, ctx.gov)

      # Full-pool sessions (no selection) issue tokens for any group.
      assert {:ok, _} = Play.create_group_token(ctx.session, fringe)
    end

    test "a group a session plays with cannot be deleted from the pool", ctx do
      {:ok, _session} =
        Play.create_session(ctx.user, ctx.scenario, %{
          label: "Small venue",
          group_ids: [ctx.gov.id, ctx.media.id]
        })

      assert {:error, changeset} = Authoring.delete_group(ctx.gov)
      assert "is used by a session and cannot be deleted" in errors_on(changeset).id

      unreferenced = group_fixture(ctx.scenario, handle: "Temp")
      assert {:ok, _} = Authoring.delete_group(unreferenced)
    end
  end
end
