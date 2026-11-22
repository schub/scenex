defmodule ScenexWeb.SessionConsoleRedirectController do
  @moduledoc false
  use ScenexWeb, :controller

  # `/console/new` was the redesigned console's path; it now lives at `/console`.
  def to_console(conn, %{"id" => id}) do
    target = ~p"/sessions/#{id}/console"
    target = if conn.query_string == "", do: target, else: target <> "?" <> conn.query_string
    redirect(conn, to: target)
  end
end
