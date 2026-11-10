defmodule Mix.Tasks.Scenex.Dashboards do
  @shortdoc "Renders the Grafana dashboards to JSON files for manual import"
  @moduledoc """
  Renders every dashboard in `Scenex.PromEx.dashboards/0` — PromEx's bundled
  ones and Scenex's own — to JSON files in a directory, for importing into
  Grafana by hand or provisioning from files:

      mix scenex.dashboards [DIR]

  `DIR` defaults to `tmp/grafana_dashboards`. The datasource uid comes from
  `GRAFANA_DATASOURCE_ID` (default `prometheus`), as for the upload on start.
  The rendering follows `PromEx.DashboardUploader`, so titles and uids match
  dashboards that were uploaded automatically.
  """
  use Mix.Task

  alias PromEx.DashboardRenderer

  @impl true
  def run(args) do
    Mix.Task.run("app.config")

    if datasource = System.get_env("GRAFANA_DATASOURCE_ID"),
      do: Application.put_env(:scenex, :grafana_datasource_id, datasource)

    dir = List.first(args) || "tmp/grafana_dashboards"
    File.mkdir_p!(dir)

    for dashboard <- Scenex.PromEx.dashboards() do
      {otp_app, path, opts} =
        case dashboard do
          {otp_app, path} -> {otp_app, path, []}
          {otp_app, path, opts} -> {otp_app, path, opts}
        end

      name = path |> Path.basename() |> Path.rootname(".eex") |> Path.rootname(".json")

      render =
        otp_app
        |> DashboardRenderer.build(path, :scenex)
        |> DashboardRenderer.merge_assigns(otp_app: :scenex)
        |> DashboardRenderer.merge_assigns(Scenex.PromEx.dashboard_assigns())
        |> DashboardRenderer.merge_assigns(
          title: "Scenex - PromEx #{Macro.camelize(name)} Dashboard"
        )
        |> DashboardRenderer.merge_assigns(opts)
        |> DashboardRenderer.render_dashboard(Scenex.PromEx)
        |> DashboardRenderer.decode_dashboard()

      case render do
        %DashboardRenderer{valid_json?: true, decoded_dashboard: json} ->
          file = Path.join(dir, name <> ".json")
          File.write!(file, Jason.encode_to_iodata!(json, pretty: true))
          Mix.shell().info("Wrote #{file}")

        %DashboardRenderer{error: error} ->
          Mix.raise("Could not render #{path}: #{inspect(error)}")
      end
    end
  end
end
