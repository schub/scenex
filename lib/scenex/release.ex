defmodule Scenex.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :scenex

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Bootstrap an owner account without email delivery.

  Creates the user (if new), confirms it, and mints a one-time magic-link
  login URL (valid 15 minutes) printed to stdout. Meant to seed the first
  account on a fresh production DB before the mailer is configured.

      bin/scenex eval 'Scenex.Release.bootstrap_owner("you@example.com")'
  """
  def bootstrap_owner(email) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    alias Scenex.Accounts
    alias Scenex.Accounts.{User, UserToken}
    alias Scenex.Repo

    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} = Accounts.register_user(%{email: email})
          user

        existing ->
          existing
      end

    user =
      if is_nil(user.confirmed_at) do
        {:ok, confirmed} = user |> User.confirm_changeset() |> Repo.update()
        confirmed
      else
        user
      end

    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    url = ScenexWeb.Endpoint.url() <> "/users/log-in/" <> encoded_token

    IO.puts("""

    === Scenex owner bootstrap ===
    Account: #{user.email} (confirmed)
    Log in within 15 minutes by opening:

    #{url}
    """)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
