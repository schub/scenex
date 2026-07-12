defmodule ScenexWeb.MediaController do
  @moduledoc """
  Serves media files under the stable public path `/media/<id>/<filename>`.

  No auth — the unguessable id is the access token, like the play QR codes.
  Handles single-part HTTP range requests, which iOS Safari requires before
  it plays video or audio at all.
  """
  use ScenexWeb, :controller

  alias Scenex.Media

  def show(conn, %{"id" => id, "filename" => filename}) do
    with %{filename: ^filename} = file <- Media.get_file(id),
         path = Scenex.Media.Storage.Local.path(Media.key(file)),
         {:ok, %File.Stat{size: size, type: :regular}} <- File.stat(path) do
      conn
      |> put_resp_content_type(file.content_type)
      |> put_resp_header("accept-ranges", "bytes")
      # The id makes the URL unique forever — cache hard.
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_ranged(path, size)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  defp send_ranged(conn, path, size) do
    case requested_range(conn, size) do
      nil ->
        send_file(conn, 200, path)

      {first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)
    end
  end

  # A single "bytes=first-last" range (either bound may be open); anything
  # unparsable or unsatisfiable falls back to the full file.
  defp requested_range(conn, size) do
    with [header] <- get_req_header(conn, "range"),
         %{"first" => first, "last" => last} <-
           Regex.named_captures(~r/^bytes=(?<first>\d*)-(?<last>\d*)$/, header),
         {first, last} <- resolve_range(first, last, size),
         true <- first <= last and first < size do
      {first, min(last, size - 1)}
    else
      _ -> nil
    end
  end

  defp resolve_range("", "", _size), do: nil
  defp resolve_range("", suffix, size), do: {max(size - String.to_integer(suffix), 0), size - 1}
  defp resolve_range(first, "", size), do: {String.to_integer(first), size - 1}
  defp resolve_range(first, last, _size), do: {String.to_integer(first), String.to_integer(last)}
end
