defmodule Scenex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    configure_mailer_tls()

    children = [
      ScenexWeb.Telemetry,
      Scenex.Repo,
      {DNSCluster, query: Application.get_env(:scenex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Scenex.PubSub},
      # Layer 3: one supervised process per running session, found by id.
      {Registry, keys: :unique, name: Scenex.Play.Registry},
      {DynamicSupervisor, name: Scenex.Play.SessionSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      ScenexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Scenex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Build the SMTP TLS options here rather than in runtime.exs. They include a
  # partial_chain anonymous function (which can't live in compile-time
  # sys.config), and :tls_certificate_check isn't loaded yet during the
  # release's config-provider boot phase. At app-start time every dependency is
  # available. Note it's an Erlang library: :tls_certificate_check, not an
  # Elixir-cased module.
  defp configure_mailer_tls do
    config = Application.get_env(:scenex, Scenex.Mailer, [])

    if config[:adapter] == Swoosh.Adapters.SMTP do
      tls_options = :tls_certificate_check.options(config[:relay])
      Application.put_env(:scenex, Scenex.Mailer, Keyword.put(config, :tls_options, tls_options))
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ScenexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
