defmodule ScenexWeb.SessionLiveTest do
  # async: false — session processes access the DB (shared sandbox).
  use ScenexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.{Authoring, Play}

  setup :register_and_log_in_user

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

    gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})
    Authoring.set_group_initial_value(gov, stability, 5.0)

    event = timeline_element_fixture(scenario, handle: "Blackout", position: 1)

    {:ok, crack} =
      Authoring.create_decision_option(event, gov, %{handle: "Crack", text: %{"en" => "Crack"}})

    Authoring.set_option_effect(crack, stability, 2.0)

    {:ok, election} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Referendum",
        title: %{"en" => "Referendum"},
        kind: :election,
        position: 2
      })

    {:ok, yes} =
      Authoring.create_decision_option(election, nil, %{handle: "Yes", text: %{"en" => "Yes"}})

    Authoring.set_option_effect(yes, stability, gov, 2.0)

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

    {:ok, ending} =
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
      event: event,
      crack: crack,
      election: election,
      yes: yes,
      sidequest: sidequest,
      success: success,
      ending: ending
    }
  end

  setup %{user: user} do
    fixtures = definition_fixture(user)
    {:ok, session} = Play.create_session(user, fixtures.scenario, %{label: "Premiere"})
    on_exit(fn -> Play.stop_running(session.id) end)
    Map.put(fixtures, :session, session)
  end

  test "creating a session from the index opens the console", %{conn: conn, scenario: scenario} do
    {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/sessions")
    assert html =~ "Premiere"

    assert {:ok, _console, html} =
             lv
             |> form("#new-session", %{"session" => %{"label" => "Second night"}})
             |> render_submit()
             |> follow_redirect(conn)

    assert html =~ "Second night"
    assert html =~ "GM console"
  end

  test "running a full session through the console", ctx do
    %{conn: conn, session: session} = ctx
    {:ok, lv, html} = live(conn, ~p"/sessions/#{session.id}/console")

    assert html =~ "Premiere"
    assert html =~ "draft"

    # Start
    html = lv |> element("button[phx-click=start]") |> render_click()
    assert html =~ "live"

    # Trigger the event and enter gov's decision -> stability 7
    lv |> element(~s{button[phx-click=trigger][phx-value-id="#{ctx.event.id}"]}) |> render_click()

    html =
      lv
      |> element(
        ~s{button[phx-click=choose][phx-value-element="#{ctx.event.id}"]} <>
          ~s{[phx-value-option="#{ctx.crack.id}"]}
      )
      |> render_click()

    assert html =~ "7"
    assert html =~ "(+2)"

    # Election: tally + winner -> gov 9
    lv
    |> element(~s{button[phx-click=trigger][phx-value-id="#{ctx.election.id}"]})
    |> render_click()

    html =
      lv
      |> form(~s{form[phx-submit=resolve_election]}, %{
        "winner" => ctx.yes.id,
        "tally" => %{ctx.yes.id => "23"}
      })
      |> render_submit()

    assert html =~ "9"
    # Declaring confirms itself: a flash plus a "decided" badge on the element.
    assert html =~ "Result declared"
    assert html =~ "decided"

    # Sidequest adjudication
    lv
    |> element(~s{button[phx-click=trigger][phx-value-id="#{ctx.sidequest.id}"]})
    |> render_click()

    lv
    |> element(
      ~s{button[phx-click=adjudicate][phx-value-element="#{ctx.sidequest.id}"]} <>
        ~s{[phx-value-option="#{ctx.success.id}"]}
    )
    |> render_click()

    # End: endings panel appears; stability global 9 >= 6 -> recommended
    html = lv |> element("button[phx-click=end_session]") |> render_click()
    assert html =~ "Choose the ending"
    assert html =~ "recommended"

    html =
      lv
      |> element(~s{button[phx-click=select_ending][phx-value-id="#{ctx.ending.id}"]})
      |> render_click()

    assert html =~ "Selected"
    assert Play.get_session!(session.id).ending_id == ctx.ending.id

    # The tally landed in the log.
    tally_event =
      session |> Play.list_session_events() |> Enum.find(&(&1.type == "election_resolved"))

    assert tally_event.payload["tally"][ctx.yes.id] == 23
  end

  test "typed tally counts survive the 1s clock refresh", ctx do
    %{conn: conn, session: session} = ctx
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session.id}/console")

    lv |> element("button[phx-click=start]") |> render_click()

    # Typing fires the change event; the clock tick re-renders — the counts
    # must be written back into the inputs, not reset to empty.
    lv
    |> form(~s{form[phx-submit=record_tally]}, %{"counts" => %{"4" => "10"}})
    |> render_change()

    send(lv.pid, :tick)

    assert lv |> element(~s{input[name="counts[4]"]}) |> render() =~ ~s(value="10")
  end

  test "typed election tallies and winner survive the 1s clock refresh", ctx do
    %{conn: conn, session: session} = ctx
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session.id}/console")

    lv |> element("button[phx-click=start]") |> render_click()

    lv
    |> element(~s{button[phx-click=trigger][phx-value-id="#{ctx.election.id}"]})
    |> render_click()

    lv
    |> form(~s{form[phx-submit=resolve_election]}, %{
      "winner" => ctx.yes.id,
      "tally" => %{ctx.yes.id => "23"}
    })
    |> render_change()

    send(lv.pid, :tick)

    assert lv |> element(~s{input[name="tally[#{ctx.yes.id}]"]}) |> render() =~ ~s(value="23")
    assert lv |> element(~s{input[type=radio][value="#{ctx.yes.id}"]}) |> render() =~ "checked"
  end

  test "recording a well-being tally", ctx do
    %{conn: conn, session: session} = ctx
    {:ok, lv, html} = live(conn, ~p"/sessions/#{session.id}/console")

    assert html =~ "Well-being"
    assert html =~ "hand count"

    lv |> element("button[phx-click=start]") |> render_click()

    # An empty tally is refused client-side with a flash.
    html = lv |> form(~s{form[phx-submit=record_tally]}) |> render_submit()
    assert html =~ "Count at least one participant"

    html =
      lv
      |> form(~s{form[phx-submit=record_tally]}, %{
        "counts" => %{"4" => "2", "3" => "1", "1" => "1"}
      })
      |> render_submit()

    # Weighted mean (4+4+3+1)/4 = 3 — latest reading and a history row appear.
    assert html =~ "🙂 3"
    assert html =~ "Average"
  end

  test "a viewer cannot open the console", %{session: session} do
    other = user_fixture()
    conn = build_conn() |> log_in_user(other)

    assert {:error, {:live_redirect, %{to: "/scenarios"}}} =
             live(conn, ~p"/sessions/#{session.id}/console")
  end

  describe "session ownership" do
    test "another author cannot open a session they did not create", ctx do
      other = user_fixture()
      {:ok, _} = Authoring.add_member(ctx.scenario, other, :author)
      conn = build_conn() |> log_in_user(other)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/sessions/#{ctx.session.id}/console")

      assert to == "/scenarios/#{ctx.scenario.id}/sessions"
      assert flash["error"] =~ "run by another GM"
    end

    test "the scenario owner can open any session (override)", ctx do
      other = user_fixture()
      {:ok, _} = Authoring.add_member(ctx.scenario, other, :author)
      {:ok, session} = Play.create_session(other, ctx.scenario, %{label: "Other night"})
      on_exit(fn -> Play.stop_running(session.id) end)

      # ctx.conn is logged in as the scenario owner.
      {:ok, _lv, html} = live(ctx.conn, ~p"/sessions/#{session.id}/console")
      assert html =~ "Other night"
    end

    test "the index shows who runs a session and hides the console link for non-GMs", ctx do
      other = user_fixture()
      {:ok, _} = Authoring.add_member(ctx.scenario, other, :author)
      conn = build_conn() |> log_in_user(other)

      {:ok, _lv, html} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/sessions")
      assert html =~ "Premiere"
      assert html =~ ctx.user.email
      refute html =~ "Open console"

      # The creator still sees their own session as "you" with the link.
      {:ok, _lv, html} = live(ctx.conn, ~p"/scenarios/#{ctx.scenario.id}/sessions")
      assert html =~ "GM: you"
      assert html =~ "Open console"
    end
  end

  test "invalid commands surface as flash, not crashes", ctx do
    %{conn: conn, session: session} = ctx
    {:ok, lv, _html} = live(conn, ~p"/sessions/#{session.id}/console")

    # The button is disabled in draft, but a stale client could still send the
    # event — the session process rejects it and the console flashes.
    html = render_click(lv, "trigger", %{"id" => ctx.event.id})

    assert html =~ "Rejected"
  end
end
