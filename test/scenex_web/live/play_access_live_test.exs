defmodule ScenexWeb.PlayAccessLiveTest do
  # async: false — session processes access the DB (shared sandbox).
  use ScenexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.{Authoring, Play}

  # No login in these tests: the token is the key.

  setup do
    gm = user_fixture()
    scenario = scenario_fixture(gm)

    stability =
      value_dimension_fixture(scenario,
        key: "stability",
        name: %{"en" => "Stability"},
        min: 0.0,
        max: 10.0
      )

    gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})
    Authoring.set_group_initial_value(gov, stability, 5.0)

    event = timeline_element_fixture(scenario, handle: "Blackout", position: 1)

    {:ok, crack} =
      Authoring.create_decision_option(event, gov, %{
        handle: "Crack",
        text: %{"en" => "Crack down"}
      })

    Authoring.set_option_effect(crack, stability, 2.0)

    {:ok, gated} =
      Authoring.create_decision_option(event, gov, %{
        handle: "Gated",
        text: %{"en" => "Locked move"},
        condition: "self(stability) >= 6"
      })

    {:ok, ending} =
      Authoring.create_ending(scenario, %{handle: "Fin", title: %{"en" => "The End"}})

    {:ok, session} = Play.create_session(gm, scenario, %{label: "Premiere"})
    on_exit(fn -> Play.stop_running(session.id) end)

    {:ok, group_token} = Play.create_group_token(session, gov)
    {:ok, display_token} = Play.create_display_token(session)

    %{
      gm: gm,
      scenario: scenario,
      stability: stability,
      gov: gov,
      event: event,
      crack: crack,
      gated: gated,
      ending: ending,
      session: session,
      group_token: group_token,
      display_token: display_token
    }
  end

  describe "tokens" do
    test "fetch_token resolves valid tokens and rejects garbage/expired", ctx do
      assert {:ok, token} = Play.fetch_token(ctx.group_token.token)
      assert token.kind == :group
      assert token.group.id == ctx.gov.id

      assert :error = Play.fetch_token("nonsense")

      past = DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)

      {:ok, expired} =
        %Scenex.Play.CapabilityToken{}
        |> Scenex.Play.CapabilityToken.changeset(%{
          session_id: ctx.session.id,
          kind: :display,
          token: Scenex.Play.CapabilityToken.generate(),
          expires_at: past
        })
        |> Scenex.Repo.insert()

      assert :error = Play.fetch_token(expired.token)
    end
  end

  describe "group view" do
    test "a group enters its decision via token — no login", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)
      {:ok, _} = Play.trigger_element(ctx.session.id, ctx.event.id)

      {:ok, lv, html} = live(build_conn(), ~p"/play/#{ctx.group_token.token}")

      assert html =~ "Government"
      assert html =~ "Blackout"
      assert html =~ "Crack down"

      html =
        lv
        |> element(
          ~s{button[phx-click=choose][phx-value-element="#{ctx.event.id}"]} <>
            ~s{[phx-value-option="#{ctx.crack.id}"]}
        )
        |> render_click()

      # 5 + 2 = 7 on the board
      assert html =~ "7"

      snap = Play.snapshot(ctx.session.id)
      assert snap.decisions[ctx.event.id][ctx.gov.id] == ctx.crack.id
    end

    test "gated options are locked for players", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)
      {:ok, _} = Play.trigger_element(ctx.session.id, ctx.event.id)

      {:ok, lv, html} = live(build_conn(), ~p"/play/#{ctx.group_token.token}")

      # Stability 5 < 6 -> locked, disabled, with the lock + condition shown.
      assert html =~ "🔒"

      locked_button =
        lv
        |> element(
          ~s{button[phx-click=choose][phx-value-element="#{ctx.event.id}"]} <>
            ~s{[phx-value-option="#{ctx.gated.id}"]}
        )
        |> render()

      assert locked_button =~ "disabled"

      # A stale client bypassing the disabled attribute is still refused.
      html = render_click(lv, "choose", %{"element" => ctx.event.id, "option" => ctx.gated.id})
      assert html =~ "can&#39;t be chosen"
      assert Play.snapshot(ctx.session.id).decisions == %{}
    end

    test "an invalid token bounces to the landing page", _ctx do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(build_conn(), ~p"/play/garbage")
    end
  end

  describe "display view" do
    test "shows the board and, after the end, the chosen ending", ctx do
      {:ok, _} = Play.start_session(ctx.session.id)

      {:ok, lv, html} = live(build_conn(), ~p"/display/#{ctx.display_token.token}")

      assert html =~ "Premiere"
      assert html =~ "Government"
      assert html =~ "Stability"

      {:ok, _} = Play.end_session(ctx.session.id)
      {:ok, _} = Play.select_ending(ctx.session.id, ctx.ending.id)

      # The display hears about it via PubSub.
      assert render(lv) =~ "The End"
    end

    test "a group token cannot open the display (and vice versa)", ctx do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(build_conn(), ~p"/display/#{ctx.group_token.token}")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(build_conn(), ~p"/play/#{ctx.display_token.token}")
    end
  end
end
