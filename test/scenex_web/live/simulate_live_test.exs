defmodule ScenexWeb.SimulateLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring

  setup :register_and_log_in_user

  defp civitas_min(%{user: user}) do
    scenario = scenario_fixture(user)

    stability =
      value_dimension_fixture(scenario,
        key: "stability",
        name: %{"en" => "Stability"},
        aggregation: "avg",
        min: 0.0,
        max: 10.0
      )

    gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})
    Authoring.set_group_initial_value(gov, stability, 5.0)

    timeline_element =
      timeline_element_fixture(scenario,
        handle: "Blackout",
        title: %{"en" => "Blackout"},
        position: 1
      )

    {:ok, option} =
      Authoring.create_decision_option(timeline_element, gov, %{
        handle: "Crack down",
        text: %{"en" => "Crack down"}
      })

    Authoring.set_option_effect(option, stability, 2.0)

    %{
      scenario: scenario,
      stability: stability,
      gov: gov,
      timeline_element: timeline_element,
      option: option
    }
  end

  setup :civitas_min

  defp toggle_selector(element_id, slot, option_id) do
    ~s{button[phx-click=toggle_option][phx-value-timeline_element="#{element_id}"]} <>
      ~s{[phx-value-slot="#{slot}"][phx-value-option="#{option_id}"]}
  end

  test "shows the starting board", %{conn: conn, scenario: scenario} do
    {:ok, _lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    assert html =~ "Dry run"
    assert html =~ "Government"
    assert html =~ "Stability"
    assert html =~ "Global"
  end

  test "picking an option applies its effect and toggling it off reverts", %{
    conn: conn,
    scenario: scenario,
    timeline_element: timeline_element,
    gov: gov,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    sel = toggle_selector(timeline_element.id, gov.id, option.id)

    html = lv |> element(sel) |> render_click()
    assert html =~ "1/1 decisions made"
    # Government stability 5 + 2 = 7
    assert html =~ "7"

    html = lv |> element(sel) |> render_click()
    assert html =~ "0/1 decisions made"
  end

  test "reset clears all selections", %{
    conn: conn,
    scenario: scenario,
    timeline_element: timeline_element,
    gov: gov,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    lv |> element(toggle_selector(timeline_element.id, gov.id, option.id)) |> render_click()
    html = lv |> element("button[phx-click=reset]") |> render_click()

    assert html =~ "0/1 decisions made"
  end

  test "an earlier decision unlocks a gated later option", %{
    conn: conn,
    scenario: scenario,
    gov: gov,
    timeline_element: element1,
    option: option1
  } do
    # Element 2 (after element 1) has an option gated on self(stability) >= 6.
    element2 =
      timeline_element_fixture(scenario,
        handle: "Aftermath",
        title: %{"en" => "Aftermath"},
        position: 2
      )

    {:ok, gated} =
      Authoring.create_decision_option(element2, gov, %{
        handle: "Push through",
        text: %{"en" => "Push through"},
        condition: "self(stability) >= 6"
      })

    {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    gated_sel = toggle_selector(element2.id, gov.id, gated.id)

    # Stability starts at 5 -> gate closed, button disabled with a lock.
    assert html =~ "🔒"
    assert lv |> element(gated_sel) |> render() =~ "disabled"

    # Picking element 1's +2 option raises stability to 7 -> gate opens.
    lv |> element(toggle_selector(element1.id, gov.id, option1.id)) |> render_click()

    refute lv |> element(gated_sel) |> render() =~ "disabled"
    assert lv |> element(gated_sel) |> render() =~ "✓"
  end

  test "declaring an election winner applies its outcome matrix", %{
    conn: conn,
    scenario: scenario,
    stability: stability,
    gov: gov
  } do
    media = group_fixture(scenario, handle: "Media", name: %{"en" => "Media"})
    Authoring.set_group_initial_value(media, stability, 5.0)

    {:ok, election} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Emergency law",
        title: %{"en" => "Emergency law"},
        kind: :election,
        position: 2
      })

    {:ok, yes} =
      Authoring.create_decision_option(election, nil, %{
        handle: "Yes",
        text: %{"en" => "Pass it"}
      })

    Authoring.set_option_effect(yes, stability, gov, 3.0)
    Authoring.set_option_effect(yes, stability, media, -2.0)

    {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    assert html =~ "declare the winning option"
    assert html =~ "Government: Stability +3"

    html = lv |> element(toggle_selector(election.id, "winner", yes.id)) |> render_click()

    # Gov 5+3=8, Media 5-2=3, global avg (8+3)/2 = 5.5
    assert html =~ "8"
    assert html =~ "3"
    assert html =~ "5.5"
  end

  test "adjudicating a sidequest applies the chosen bundle", %{
    conn: conn,
    scenario: scenario,
    stability: stability,
    gov: gov
  } do
    {:ok, sidequest} =
      Authoring.create_timeline_element(scenario, %{
        handle: "Leak",
        title: %{"en" => "Leak"},
        kind: :sidequest,
        position: 2
      })

    {:ok, success} =
      Authoring.create_decision_option(sidequest, nil, %{
        handle: "It worked",
        text: %{"en" => "It worked"},
        outcome: :success
      })

    Authoring.set_option_effect(success, stability, gov, 2.0)

    {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    assert html =~ "GM adjudicates"

    html = lv |> element(toggle_selector(sidequest.id, "outcome", success.id)) |> render_click()

    # Gov stability 5 + 2 = 7
    assert html =~ "7"
    assert html =~ "1/2 decisions made"
  end

  test "endings are recommended by the current board", %{
    conn: conn,
    scenario: scenario,
    timeline_element: element,
    gov: gov,
    option: option
  } do
    {:ok, _stable} =
      Authoring.create_ending(scenario, %{
        handle: "Stabilized",
        title: %{"en" => "Stabilized"},
        condition: "global(stability) >= 6"
      })

    {:ok, _open} =
      Authoring.create_ending(scenario, %{
        handle: "Muddling through",
        title: %{"en" => "Muddling through"}
      })

    {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}/simulate")

    # Start: stability 5 -> condition not met
    assert html =~ "not matching"
    assert html =~ "no condition"
    refute html =~ ">recommended<"

    # +2 stability -> global 7 -> recommended
    html = lv |> element(toggle_selector(element.id, gov.id, option.id)) |> render_click()
    assert html =~ "recommended"
  end
end
