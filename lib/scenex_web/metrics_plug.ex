defmodule ScenexWeb.MetricsPlug do
  @moduledoc """
  The whole app of the metrics listener: `GET /metrics` in Prometheus text
  format (via `PromEx.Plug`), 404 for anything else. Started by
  `Scenex.Application` on its own port, which the edge nginx does not proxy.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(_opts), do: PromEx.Plug.init(prom_ex_module: Scenex.PromEx, path: "/metrics")

  @impl true
  def call(conn, opts) do
    conn = PromEx.Plug.call(conn, opts)
    if conn.halted, do: conn, else: send_resp(conn, 404, "Not Found")
  end
end
