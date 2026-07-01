defmodule Scenex.Repo do
  use Ecto.Repo,
    otp_app: :scenex,
    adapter: Ecto.Adapters.Postgres
end
