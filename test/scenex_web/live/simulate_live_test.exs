defmodule ScenexWeb.SimulateLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring

  setup :register_and_log_in_user

  defp civitas_min(%{user: user}) do
    game = game_fixture(user)

    stability =
      value_definition_fixture(game,
        key: "stability",
        name: %{"en" => "Stability"},
        aggregation: "avg",
        min: 0.0,
        max: 10.0
      )

    gov = group_fixture(game, handle: "Gov", name: %{"en" => "Government"})
    Authoring.set_group_initial_value(gov, stability, 5.0)

    event = event_fixture(game, handle: "Blackout", title: %{"en" => "Blackout"})

    {:ok, option} =
      Authoring.create_decision_option(event, gov, %{
        handle: "Crack down",
        text: %{"en" => "Crack down"}
      })

    Authoring.set_option_effect(option, stability, 2.0)

    %{game: game, stability: stability, gov: gov, event: event, option: option}
  end

  setup :civitas_min

  test "shows the starting board", %{conn: conn, game: game} do
    {:ok, _lv, html} = live(conn, ~p"/games/#{game.id}/simulate")

    assert html =~ "Dry run"
    assert html =~ "Government"
    assert html =~ "Stability"
    assert html =~ "Global"
  end

  test "picking an option applies its effect and toggling it off reverts", %{
    conn: conn,
    game: game,
    event: event,
    gov: gov,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}/simulate")

    sel =
      ~s{button[phx-click=toggle_option][phx-value-event="#{event.id}"]} <>
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
    game: game,
    event: event,
    gov: gov,
    option: option
  } do
    {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}/simulate")

    sel =
      ~s{button[phx-click=toggle_option][phx-value-event="#{event.id}"]} <>
        ~s{[phx-value-group="#{gov.id}"][phx-value-option="#{option.id}"]}

    lv |> element(sel) |> render_click()
    html = lv |> element("button[phx-click=reset]") |> render_click()

    assert html =~ "0/1 decisions made"
  end
end
