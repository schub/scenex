defmodule ScenexWeb.ScenarioLiveTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring

  setup :register_and_log_in_user

  describe "Index" do
    test "creating a scenario redirects into the editor", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#new-scenario", %{
                 "scenario" => %{"handle" => "My Scenario", "source_locale" => "en"}
               })
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "My Scenario"
    end

    test "lists scenarios the user can see", %{conn: conn, user: user} do
      scenario = scenario_fixture(user, handle: "Listed Scenario")
      {:ok, _lv, html} = live(conn, ~p"/scenarios")
      assert html =~ "Listed Scenario"
      assert html =~ "/scenarios/#{scenario.id}"
    end
  end

  describe "Show editor" do
    setup %{user: user} do
      %{scenario: scenario_fixture(user)}
    end

    test "adds a value definition", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")

      lv |> element("button[phx-value-section=values]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_value"]), %{
          "value_dimension" => %{
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

    test "rejects an invalid aggregation formula", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=values]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_value"]), %{
          "value_dimension" => %{
            "key" => "risk",
            "aggregation" => "bogus(",
            "input_scope" => "per_group",
            "name" => %{"en" => "Risk"}
          }
        })
        |> render_submit()

      assert html =~ "not a valid formula"
    end

    test "adds a group", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=groups]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_group"]), %{
          "group" => %{"handle" => "Gov", "name" => %{"en" => "Government"}, "position" => "0"}
        })
        |> render_submit()

      assert html =~ "Government"
    end

    test "redirects when the scenario is not accessible", %{conn: conn} do
      other = user_fixture()
      hidden = scenario_fixture(other)

      assert {:error, {:live_redirect, %{to: "/scenarios"}}} =
               live(conn, ~p"/scenarios/#{hidden.id}")
    end

    test "adds a timeline element", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=timeline]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_event"]), %{
          "timeline_element" => %{
            "handle" => "Blackout",
            "title" => %{"en" => "Blackout"},
            "kind" => "event",
            "position" => "0"
          }
        })
        |> render_submit()

      assert html =~ "Blackout"
    end

    test "adds a label", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
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

    test "adds a decision option with an effect and a label", %{conn: conn, scenario: scenario} do
      value = value_dimension_fixture(scenario, key: "stability", name: %{"en" => "Stability"})
      group = group_fixture(scenario, name: %{"en" => "Government"})
      timeline_element = timeline_element_fixture(scenario, title: %{"en" => "Blackout"})
      label = label_fixture(scenario, name: %{"en" => "Aggressive"}, color: :error)

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=timeline]") |> render_click()

      lv
      |> element(~s{button[phx-click=open_event][phx-value-id="#{timeline_element.id}"]})
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

      [option] = Authoring.list_decision_options(timeline_element)
      assert [%{delta: -5.0}] = option.effects
      assert [%{name: %{"en" => "Aggressive"}}] = option.labels
    end
  end
end
