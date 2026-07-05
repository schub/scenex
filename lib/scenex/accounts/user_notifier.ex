defmodule Scenex.Accounts.UserNotifier do
  import Swoosh.Email

  alias Scenex.Mailer
  alias Scenex.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Scenex", "noreply@scenex.org"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver an invitation to join a scenario (recipient has no account yet).
  """
  def deliver_scenario_invitation(email, scenario_name, role, url) do
    deliver(email, "You've been invited to \"#{scenario_name}\" on Scenex", """

    ==============================

    Hi #{email},

    You've been invited to join the scenario "#{scenario_name}" as #{role}
    on Scenex.

    Create your account and join by visiting the URL below:

    #{url}

    The invitation is valid for 7 days. If you weren't expecting this,
    please ignore this email.

    ==============================
    """)
  end

  @doc """
  Notify an existing user that they were added to a scenario.
  """
  def deliver_added_to_scenario(user, scenario_name, role) do
    deliver(user.email, "You've been added to \"#{scenario_name}\" on Scenex", """

    ==============================

    Hi #{user.email},

    You've been added to the scenario "#{scenario_name}" as #{role} on Scenex.

    Log in to see it in your scenario list.

    ==============================
    """)
  end
end
