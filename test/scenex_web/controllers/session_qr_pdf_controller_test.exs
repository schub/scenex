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

  test "auto-generates every missing code on first download — no clicking required", %{
    conn: conn,
    session: session,
    gov: gov,
    scenario: scenario
  } do
    opp = group_fixture(scenario, handle: "Opp", name: %{"en" => "Opposition"})

    assert Play.list_tokens(session) == []

    conn = get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    assert response_content_type(conn, :pdf)
    assert String.starts_with?(response(conn, 200), "%PDF-")

    tokens = Play.list_tokens(session)
    assert length(tokens) == 2
    assert Enum.any?(tokens, &(&1.kind == :group and &1.group_id == gov.id))
    refute Enum.any?(tokens, &(&1.kind == :group and &1.group_id == opp.id))
    assert Enum.any?(tokens, &(&1.kind == :display))
  end

  test "downloading again reuses existing codes instead of minting duplicates", %{
    conn: conn,
    session: session,
    gov: gov
  } do
    {:ok, token} = Play.create_group_token(session, gov)

    get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    tokens = Play.list_tokens(session)
    assert length(tokens) == 2
    assert Enum.find(tokens, &(&1.kind == :group)).id == token.id
  end

  test "a user with no access to the scenario is redirected", %{session: session} do
    conn = build_conn() |> log_in_user(user_fixture())

    conn = get(conn, ~p"/sessions/#{session.id}/qr_codes.pdf")

    assert redirected_to(conn) == ~p"/scenarios/#{session.scenario_id}/sessions"
  end
end
