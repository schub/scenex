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
      timeline_element_fixture(scenario, handle: "Blackout", title: %{"en" => "Blackout"})

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

    sel =
      ~s{button[phx-click=toggle_option][phx-value-timeline_element="#{timeline_element.id}"]} <>
        ~s{[phx-value-group="#{gov.id}"][phx-value-option="#{option.id}"]}

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

    sel =
      ~s{button[phx-click=toggle_option][phx-value-timeline_element="#{timeline_element.id}"]} <>
        ~s{[phx-value-group="#{gov.id}"][phx-value-option="#{option.id}"]}

    lv |> element(sel) |> render_click()
    html = lv |> element("button[phx-click=reset]") |> render_click()

    assert html =~ "0/1 decisions made"
  end
end
