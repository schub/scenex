defmodule Scenex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ScenexWeb.Telemetry,
      Scenex.Repo,
      {DNSCluster, query: Application.get_env(:scenex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Scenex.PubSub},
      # Start a worker by calling: Scenex.Worker.start_link(arg)
      # {Scenex.Worker, arg},
      # Start to serve requests, typically the last entry
      ScenexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Scenex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ScenexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
