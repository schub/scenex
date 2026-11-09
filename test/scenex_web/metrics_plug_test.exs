defmodule ScenexWeb.MetricsPlugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias ScenexWeb.MetricsPlug

  defp call(path), do: conn(:get, path) |> MetricsPlug.call(MetricsPlug.init([]))

  test "serves /metrics (503 while PromEx is disabled, as in test)" do
    capture_log(fn -> assert call("/metrics").status == 503 end)
  end

  test "anything else is not found" do
    assert call("/").status == 404
    assert call("/users/log-in").status == 404
  end
end
