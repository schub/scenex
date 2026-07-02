defmodule ScenexWeb.GameLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring

  setup :register_and_log_in_user

  describe "Index" do
    test "creating a game redirects into the editor", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/games")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#new-game", %{"game" => %{"handle" => "My Game", "source_locale" => "en"}})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "My Game"
    end

    test "lists games the user can see", %{conn: conn, user: user} do
      game = game_fixture(user, handle: "Listed Game")
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
          "group" => %{"handle" => "Gov", "name" => %{"en" => "Government"}, "position" => "0"}
        })
        |> render_submit()

      assert html =~ "Government"
    end

    test "redirects when the game is not accessible", %{conn: conn} do
      other = user_fixture()
      hidden = game_fixture(other)

      assert {:error, {:live_redirect, %{to: "/games"}}} = live(conn, ~p"/games/#{hidden.id}")
    end

    test "adds an event", %{conn: conn, game: game} do
      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")
      lv |> element("button[phx-value-section=events]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_event"]), %{
          "event" => %{
            "handle" => "Blackout",
            "title" => %{"en" => "Blackout"},
            "kind" => "event",
            "position" => "0"
          }
        })
        |> render_submit()

      assert html =~ "Blackout"
    end

    test "adds a label", %{conn: conn, game: game} do
      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")
      lv |> element("button[phx-value-section=labels]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_label"]), %{
          "label" => %{
            "handle" => "Aggressive",
            "name" => %{"en" => "Aggressive"},
            "color" => "error",
            "position" => "0"
          }
        })
        |> render_submit()

      assert html =~ "Aggressive"
    end

    test "adds a decision option with an effect and a label", %{conn: conn, game: game} do
      value = value_definition_fixture(game, key: "stability", name: %{"en" => "Stability"})
      group = group_fixture(game, name: %{"en" => "Government"})
      event = event_fixture(game, title: %{"en" => "Blackout"})
      label = label_fixture(game, name: %{"en" => "Aggressive"}, color: :error)

      {:ok, lv, _html} = live(conn, ~p"/games/#{game.id}")
      lv |> element("button[phx-value-section=events]") |> render_click()

      lv
      |> element(~s{button[phx-click=open_event][phx-value-id="#{event.id}"]})
      |> render_click()

      lv
      |> element(~s{button[phx-click=new_option][phx-value-group="#{group.id}"]})
      |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_option"]), %{
          "option" => %{
            "handle" => "Ration",
            "text" => %{"en" => "Ration power"},
            "position" => "0",
            "labels" => [label.id]
          },
          "effect" => %{value.id => "-5"}
        })
        |> render_submit()

      assert html =~ "Ration power"
      assert html =~ "Aggressive"
      assert html =~ "Stability -5"

      [option] = Authoring.list_decision_options(event)
      assert [%{delta: -5.0}] = option.effects
      assert [%{name: %{"en" => "Aggressive"}}] = option.labels
    end
  end
end
