defmodule ScenexWeb.HomeLiveTest do
  use ScenexWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the landing page and shows a connected socket", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert html =~ "Scenex"
    # In LiveView tests the socket is connected, so mount reports connectivity.
    assert render(lv) =~ "connected"
    assert has_element?(lv, "p.tabular-nums", "0")
  end

  test "the counter increments over the socket", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    lv |> element("button[phx-click=inc]") |> render_click()
    assert has_element?(lv, "p.tabular-nums", "1")

    lv |> element("button[phx-click=inc]") |> render_click()
    assert has_element?(lv, "p.tabular-nums", "2")
  end
end
