defmodule ScenexWeb.GameLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "creating a game redirects into the editor", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/games")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#new-game", %{"game" => %{"name" => "My Game", "source_locale" => "en"}})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "My Game"
    end

    test "lists games the user can see", %{conn: conn, user: user} do
      game = game_fixture(user, name: %{"en" => "Listed Game"})
      {:ok, _lv, html} = live(conn, ~p"/games")
      assert html =~ "Listed Game"
      assert html =~ "/games/#{game.id}"
    end
  end

  describe "Show editor" do
    setup %{user: user} do
      %{game: game_fixture(user)}
    end

    test "adds a value definition", %{conn: conn, game: game} do
      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")

      lv |> element("button[phx-value-section=values]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_value"]), %{
          "value_definition" => %{
            "key" => "stability",
            "aggregation" => "avg",
            "input_scope" => "per_group",
            "name" => %{"en" => "Stability"}
          }
        })
        |> render_submit()

      assert html =~ "stability"
      assert html =~ "Stability"
    end

    test "rejects an invalid aggregation formula", %{conn: conn, game: game} do
      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")
      lv |> element("button[phx-value-section=values]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_value"]), %{
          "value_definition" => %{
            "key" => "risk",
            "aggregation" => "bogus(",
            "input_scope" => "per_group",
            "name" => %{"en" => "Risk"}
          }
        })
        |> render_submit()

      assert html =~ "not a valid formula"
    end

    test "adds a group", %{conn: conn, game: game} do
      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")
      lv |> element("button[phx-value-section=groups]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_group"]), %{
          "group" => %{"name" => %{"en" => "Government"}, "position" => "0"}
        })
        |> render_submit()

      assert html =~ "Government"
    end

    test "redirects when the game is not accessible", %{conn: conn} do
      other = user_fixture()
      hidden = game_fixture(other)

      assert {:error, {:live_redirect, %{to: "/games"}}} = live(conn, ~p"/games/#{hidden.id}")
    end
  end
end
