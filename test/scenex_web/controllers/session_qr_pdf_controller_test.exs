defmodule ScenexWeb.SessionQrPdfControllerTest do
  use ScenexWeb.ConnCase, async: false

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Play

  setup :register_and_log_in_user

  setup %{user: user} do
    scenario = scenario_fixture(user)
    gov = group_fixture(scenario, handle: "Gov", name: %{"en" => "Government"})
    {:ok, session} = Play.create_session(user, scenario, %{label: "Premiere"})
    on_exit(fn -> Play.stop_running(session.id) end)

    %{scenario: scenario, gov: gov, session: session}
  end

  test "downloads a PDF with every token's QR code, wrapping long group names", %{
    conn: conn,
    gov: gov,
    scenario: scenario,
    user: user
  } do
    opp = group_fixture(scenario, handle: "Opp", name: %{"en" => "Opposition"})

    media =
      group_fixture(scenario,
        handle: "Media",
        name: %{"en" => "Independent Press & Broadcasters Association"}
      )

    {:ok, session} = Play.create_session(user, scenario, %{label: "Premiere"})
    on_exit(fn -> Play.stop_running(session.id) end)

    {:ok, _} = Play.create_group_token(session, gov)
    {:ok, _} = Play.create_group_token(session, opp)
    {:ok, _} = Play.create_group_token(session, media)
    {:ok, _} = Play.create_display_token(session)

    conn = get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    assert response_content_type(conn, :pdf)
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "premiere-access-codes.pdf"

    body = response(conn, 200)
    assert byte_size(body) > 0
    assert String.starts_with?(body, "%PDF-")
  end

  test "still returns a PDF when no tokens have been generated yet", %{
    conn: conn,
    session: session
  } do
    conn = get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    assert response_content_type(conn, :pdf)
    assert String.starts_with?(response(conn, 200), "%PDF-")
  end

  test "a user with no access to the scenario is redirected", %{session: session} do
    conn = build_conn() |> log_in_user(user_fixture())

    conn = get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    assert redirected_to(conn) == ~p"/scenarios/#{session.scenario_id}/sessions"
  end
end
