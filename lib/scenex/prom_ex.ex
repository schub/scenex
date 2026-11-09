defmodule Scenex.PromEx do
  @moduledoc """
  Platform metrics in Prometheus format (ADR 0026,
  `docs/adr/0026-metrics-prometheus-grafana.md`).

  Collects the built-in PromEx plugins (BEAM, application, Phoenix, LiveView,
  Ecto) plus `Scenex.PromEx.ScenexPlugin` for live shows and platform usage.
  Metrics are served by `ScenexWeb.MetricsPlug` on a listener of their own
  (`config :scenex, :metrics_server`), never on the public endpoint.

  Dashboards: PromEx's bundled ones plus `priv/grafana_dashboards/scenex.json.eex`.
  When `GRAFANA_URL` and `GRAFANA_TOKEN` are set, they are uploaded to Grafana
  on start (see `config/runtime.exs`); otherwise export them with
  `mix prom_ex.dashboard.export`.
  """
  use PromEx, otp_app: :scenex

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: ScenexWeb.Router, endpoint: ScenexWeb.Endpoint},
      Plugins.Ecto,
      Plugins.PhoenixLiveView,
      Scenex.PromEx.ScenexPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: Application.get_env(:scenex, :grafana_datasource_id, "prometheus"),
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "phoenix_live_view.json"},
      {:scenex, "/grafana_dashboards/scenex.json", title: "Scenex - Platform"}
    ]
  end
end
