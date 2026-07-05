defmodule ScenexWeb.UserLive.AcceptInviteTest do
  use ScenexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring

  defp invite(scenario, owner, email, role \\ :author) do
    test_pid = self()

    {:ok, :invitation_sent} =
      Authoring.invite_member(scenario, owner, email, role, fn token ->
        send(test_pid, {:invite_token, token})
        "http://localhost/invites/#{token}"
      end)

    assert_received {:invite_token, token}
    token
  end

  test "an invalid token redirects to login with an error", %{conn: conn} do
    {:error, {:live_redirect, %{to: "/users/log-in", flash: flash}}} =
      live(conn, ~p"/invites/bogus-token")

    assert flash["error"] =~ "invalid or it has expired"
  end

  test "a valid token shows the join form with the invited email", %{conn: conn} do
    owner = user_fixture()
    scenario = scenario_fixture(owner)
    token = invite(scenario, owner, "newcomer@example.com")

    {:ok, _lv, html} = live(conn, ~p"/invites/#{token}")

    assert html =~ "newcomer@example.com"
    assert html =~ "Create account &amp; join"
  end

  test "submitting a valid password creates the account and membership", %{conn: conn} do
    owner = user_fixture()
    scenario = scenario_fixture(owner)
    token = invite(scenario, owner, "newcomer@example.com")

    {:ok, lv, _html} = live(conn, ~p"/invites/#{token}")

    form =
      form(lv, "#accept_invite_form",
        user: %{
          email: "newcomer@example.com",
          password: "hello world!!",
          password_confirmation: "hello world!!"
        }
      )

    render_submit(form)

    user = Scenex.Accounts.get_user_by_email("newcomer@example.com")
    assert user
    assert user.confirmed_at
    assert Authoring.get_user_role(scenario, user) == :author
    assert Authoring.list_pending_invitations(scenario) == []

    # The form then posts the credentials to the session controller,
    # landing the user logged in at the signed-in path.
    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
  end

  test "rejects a too-short password and keeps the invitation", %{conn: conn} do
    owner = user_fixture()
    scenario = scenario_fixture(owner)
    token = invite(scenario, owner, "newcomer@example.com")

    {:ok, lv, _html} = live(conn, ~p"/invites/#{token}")

    html =
      lv
      |> form("#accept_invite_form", user: %{password: "short", password_confirmation: "short"})
      |> render_submit()

    assert html =~ "should be at least 12 character"
    assert Scenex.Accounts.get_user_by_email("newcomer@example.com") == nil
    assert [_invitation] = Authoring.list_pending_invitations(scenario)
  end

  test "a logged-in user with the invited email joins directly", %{conn: conn} do
    owner = user_fixture()
    scenario = scenario_fixture(owner)
    # Invitation predates the account (otherwise membership is added directly).
    token = invite(scenario, owner, "late@example.com")
    invitee = user_fixture(%{email: "late@example.com"})

    conn = log_in_user(conn, invitee)

    {:error, {:live_redirect, %{to: to, flash: flash}}} = live(conn, ~p"/invites/#{token}")

    assert to == "/scenarios/#{scenario.id}"
    assert flash["info"] =~ "joined"
    assert Authoring.get_user_role(scenario, invitee) == :author
  end

  test "a logged-in user with a different email is told to log out", %{conn: conn} do
    owner = user_fixture()
    scenario = scenario_fixture(owner)
    other = user_fixture()
    token = invite(scenario, owner, "someone-else@example.com")

    conn = log_in_user(conn, other)

    {:error, {:live_redirect, %{to: "/scenarios", flash: flash}}} =
      live(conn, ~p"/invites/#{token}")

    assert flash["error"] =~ "Log out first"
  end
end
