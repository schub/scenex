defmodule ScenexWeb.HomeLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "shows sign-in options to a visitor", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Scenex"
    # Registration is invitation-only; the landing page offers login only.
    refute html =~ ~p"/users/register"
    assert html =~ ~p"/users/log-in"
  end

  test "shows a scenarios link to a logged-in user", %{conn: conn} do
    conn = register_and_log_in_user(%{conn: conn}).conn
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ ~p"/scenarios"
  end
end
