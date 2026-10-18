# Prepares the tutorial database: one confirmed account with a password, and
# the Mars Colony scenario seeded for it. Run by tutorial/run.sh.
#
#     SCENEX_DEV_DATABASE=scenex_tutorial mix run tutorial/setup.exs

alias Scenex.{Accounts, Repo}

email = System.get_env("TUTORIAL_EMAIL", "director@mars-colony.example")
password = System.get_env("TUTORIAL_PASSWORD", "red-planet-2026")

unless Repo.get_by(Accounts.User, email: email) do
  {:ok, _} =
    Accounts.register_invited_user(email, %{
      password: password,
      password_confirmation: password
    })
end

System.put_env("MARS_OWNER_EMAIL", email)
Code.require_file("priv/repo/seeds_mars_colony.exs")
