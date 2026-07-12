defmodule ScenexWeb.MediaControllerTest do
  use ScenexWeb.ConnCase, async: true

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Media

  setup do
    user = user_fixture()
    scenario = scenario_fixture(user)

    source = Path.join(System.tmp_dir!(), "media_ctrl_#{System.unique_integer([:positive])}")
    File.write!(source, "0123456789")
    on_exit(fn -> File.rm(source) end)

    {:ok, media_file} =
      Media.create_file(scenario, user, %{
        path: source,
        filename: "clip.mp4",
        content_type: "video/mp4",
        size: 10
      })

    %{media_file: media_file}
  end

  test "serves the file publicly with type, caching, and range support", %{
    conn: conn,
    media_file: media_file
  } do
    conn = get(conn, "/media/#{media_file.id}/clip.mp4")

    assert response(conn, 200) == "0123456789"
    assert response_content_type(conn, :mp4) =~ "video/mp4"
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "immutable"
  end

  test "answers a range request with 206 and the right slice", %{
    conn: conn,
    media_file: media_file
  } do
    conn =
      conn
      |> put_req_header("range", "bytes=2-5")
      |> get("/media/#{media_file.id}/clip.mp4")

    assert response(conn, 206) == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]

    # Open-ended range (how Safari probes before playing).
    conn =
      build_conn()
      |> put_req_header("range", "bytes=8-")
      |> get("/media/#{media_file.id}/clip.mp4")

    assert response(conn, 206) == "89"
  end

  test "unknown ids, wrong filenames, and junk 404", %{conn: conn, media_file: media_file} do
    assert conn |> get("/media/#{media_file.id}/other.mp4") |> response(404)
    assert build_conn() |> get("/media/#{Ecto.UUID.generate()}/clip.mp4") |> response(404)
    assert build_conn() |> get("/media/not-a-uuid/clip.mp4") |> response(404)
  end
end
