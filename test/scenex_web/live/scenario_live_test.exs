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

    test "locale switch shows each locale's own draft, and one save persists all",
         %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")

      # Type an English draft (not saved yet)...
      lv
      |> form(~s(form[phx-submit="save_settings"]))
      |> render_change(%{"scenario" => %{"description" => %{"en" => "English draft"}}})

      # ...switch to Polish: the field must look empty, not keep the EN text.
      html =
        lv |> element(~s(button[phx-click="set_locale"][phx-value-locale="pl"])) |> render_click()

      refute html =~ "English draft"

      # Type the Polish draft, then switch back: the EN draft is still there.
      lv
      |> form(~s(form[phx-submit="save_settings"]))
      |> render_change(%{"scenario" => %{"description" => %{"pl" => "Polski szkic"}}})

      html =
        lv |> element(~s(button[phx-click="set_locale"][phx-value-locale="en"])) |> render_click()

      assert html =~ "English draft"
      refute html =~ "Polski szkic"

      # One save persists both locales.
      lv
      |> form(~s(form[phx-submit="save_settings"]), %{
        "scenario" => %{"handle" => scenario.handle}
      })
      |> render_submit()

      assert Authoring.get_scenario!(scenario.id).description == %{
               "en" => "English draft",
               "pl" => "Polski szkic"
             }
    end

    test "an empty locale never shows another locale's saved text", %{conn: conn, user: user} do
      scenario =
        scenario_fixture(user, description: %{"en" => "Saved English description"})

      {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}")
      assert html =~ "Saved English description"

      html =
        lv |> element(~s(button[phx-click="set_locale"][phx-value-locale="pl"])) |> render_click()

      refute html =~ "Saved English description"
    end

    test "saves settings with a localized tagline", %{conn: conn, scenario: scenario} do
      {:ok, lv, html} = live(conn, ~p"/scenarios/#{scenario.id}")

      assert html =~ "Tagline"

      lv
      |> form(~s(form[phx-submit="save_settings"]), %{
        "scenario" => %{
          "handle" => scenario.handle,
          "tagline" => %{"en" => "Democracy under pressure"}
        }
      })
      |> render_submit()

      assert Authoring.get_scenario!(scenario.id).tagline == %{
               "en" => "Democracy under pressure"
             }
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

    test "the option editor replaces the element pane and Back returns", %{
      conn: conn,
      scenario: scenario
    } do
      group = group_fixture(scenario, name: %{"en" => "Government"})
      element = timeline_element_fixture(scenario, title: %{"en" => "Blackout"})

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=timeline]") |> render_click()

      # Selecting an element in the sidebar shows its editor + options.
      html =
        lv
        |> element(~s{button[phx-click=open_event][phx-value-id="#{element.id}"]})
        |> render_click()

      assert html =~ "Edit element —"
      assert html =~ "Options — Blackout"

      # Opening an option swaps the pane: breadcrumb + back, element form gone.
      html =
        lv
        |> element(~s{button[phx-click=new_option][phx-value-group="#{group.id}"]})
        |> render_click()

      assert html =~ "← Back"
      assert html =~ "New option"
      refute html =~ "Edit element —"

      # Back restores the element pane.
      html = lv |> element("button[phx-click=cancel_option]", "← Back") |> render_click()
      refute html =~ "← Back"
      assert html =~ "Edit element —"
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

    test "edits an election option with an outcome matrix", %{conn: conn, scenario: scenario} do
      value = value_dimension_fixture(scenario, key: "stability", name: %{"en" => "Stability"})
      gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})
      media = group_fixture(scenario, handle: "Media", name: %{"en" => "Media"})

      {:ok, election} =
        Authoring.create_timeline_element(scenario, %{
          handle: "Emergency law",
          title: %{"en" => "Emergency law"},
          kind: :election
        })

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=timeline]") |> render_click()

      lv
      |> element(~s{button[phx-click=open_event][phx-value-id="#{election.id}"]})
      |> render_click()

      # Election panel shows the room-wide ballot, not per-group blocks
      assert render(lv) =~ "Ballot options"

      lv |> element(~s{button[phx-click=new_option]:not([phx-value-group])}) |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_option"]), %{
          "option" => %{
            "handle" => "Yes",
            "text" => %{"en" => "Pass the law"},
            "position" => "0",
            "condition" => "global(stability) < 8"
          },
          "matrix" => %{
            gov.id => %{value.id => "2"},
            media.id => %{value.id => "-1"}
          }
        })
        |> render_submit()

      assert html =~ "Yes"
      assert html =~ "Government: Stability +2"
      assert html =~ "Media: Stability -1"

      [option] = Authoring.list_decision_options(election)
      assert option.group_id == nil
      assert option.condition == "global(stability) < 8"
      assert length(option.effects) == 2
    end

    test "defines sidequest success and failure outcomes", %{conn: conn, scenario: scenario} do
      value = value_dimension_fixture(scenario, key: "solidarity", name: %{"en" => "Solidarity"})
      gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})

      {:ok, sidequest} =
        Authoring.create_timeline_element(scenario, %{
          handle: "Leak the memo",
          title: %{"en" => "Leak the memo"},
          kind: :sidequest
        })

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=timeline]") |> render_click()

      lv
      |> element(~s{button[phx-click=open_event][phx-value-id="#{sidequest.id}"]})
      |> render_click()

      lv
      |> element(~s{button[phx-click=new_outcome][phx-value-outcome="success"]})
      |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_option"]), %{
          "option" => %{
            "handle" => "Memo published",
            "text" => %{"en" => "The memo goes public"},
            "position" => "0",
            "outcome" => "success"
          },
          "matrix" => %{gov.id => %{value.id => "1"}}
        })
        |> render_submit()

      assert html =~ "Memo published"

      [option] = Authoring.list_decision_options(sidequest)
      assert option.outcome == :success
      assert [%{delta: 1.0, group_id: group_id}] = option.effects
      assert group_id == gov.id

      # The success slot is filled; only failure can still be defined
      refute has_element?(lv, ~s{button[phx-click=new_outcome][phx-value-outcome="success"]})
      assert has_element?(lv, ~s{button[phx-click=new_outcome][phx-value-outcome="failure"]})
    end

    test "adds an ending with a condition", %{conn: conn, scenario: scenario} do
      value_dimension_fixture(scenario, key: "risk", name: %{"en" => "Risk"})

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=endings]") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save_ending"]), %{
          "ending" => %{
            "handle" => "Collapse",
            "title" => %{"en" => "Systemic collapse"},
            "condition" => "global(risk) >= 8",
            "priority" => "10"
          }
        })
        |> render_submit()

      assert html =~ "Collapse"
      assert html =~ "global(risk) &gt;= 8"

      # invalid condition is rejected with a readable error
      html2 =
        lv
        |> form(~s(form[phx-submit="save_ending"]), %{
          "ending" => %{
            "handle" => "Bad",
            "title" => %{"en" => "Bad"},
            "condition" => "self(risk) >= 8"
          }
        })
        |> render_submit()

      assert html2 =~ "self(...) is not allowed here"
    end

    test "uploads and deletes a media file", %{conn: conn, scenario: scenario} do
      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")

      lv |> element("button[phx-value-section=media]") |> render_click()

      lv
      |> file_input(~s(form[phx-submit="save_media"]), :media, [
        %{
          name: "poster.png",
          content: "fake png bytes",
          type: "image/png"
        }
      ])
      |> render_upload("poster.png")

      html = lv |> form(~s(form[phx-submit="save_media"])) |> render_submit()
      assert html =~ "poster.png"
      assert html =~ "Copy link"

      assert [file] = Scenex.Media.list_files(scenario)
      assert file.filename == "poster.png"

      html =
        lv
        |> element(~s(button[phx-click="delete_media"][phx-value-id="#{file.id}"]))
        |> render_click()

      refute html =~ "poster.png"
      assert Scenex.Media.list_files(scenario) == []
    end

    test "saves director's notes on a group", %{conn: conn, scenario: scenario} do
      group = group_fixture(scenario, name: %{"en" => "Government"})

      {:ok, lv, _html} = live(conn, ~p"/scenarios/#{scenario.id}")
      lv |> element("button[phx-value-section=groups]") |> render_click()

      lv
      |> element(~s{button[phx-click=edit_group][phx-value-id="#{group.id}"]})
      |> render_click()

      lv
      |> form(~s(form[phx-submit="save_group"]), %{
        "group" => %{
          "handle" => group.handle,
          "name" => %{"en" => "Government"},
          "director_notes" => %{"en" => "Seat them near the stage."},
          "position" => "0"
        }
      })
      |> render_submit()

      assert Authoring.get_group!(group.id).director_notes["en"] == "Seat them near the stage."
    end
  end
end
