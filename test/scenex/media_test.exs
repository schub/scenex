defmodule Scenex.MediaTest do
  use Scenex.DataCase, async: true

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Media
  alias Scenex.Media.Storage.Local

  setup do
    user = user_fixture()
    scenario = scenario_fixture(user)

    source = Path.join(System.tmp_dir!(), "media_source_#{System.unique_integer([:positive])}")
    File.write!(source, "fake image bytes")
    on_exit(fn -> File.rm(source) end)

    %{user: user, scenario: scenario, source: source}
  end

  defp attrs(source, overrides \\ %{}) do
    Map.merge(
      %{path: source, filename: "poster.png", content_type: "image/png", size: 16},
      overrides
    )
  end

  test "create, list, and delete a file (row and bytes)", %{
    user: user,
    scenario: scenario,
    source: source
  } do
    assert {:ok, file} = Media.create_file(scenario, user, attrs(source))
    assert file.filename == "poster.png"
    assert file.uploaded_by_id == user.id
    assert Media.kind(file) == :image
    assert Media.public_path(file) == "/media/#{file.id}/poster.png"

    disk = Local.path(Media.key(file))
    assert File.read!(disk) == "fake image bytes"

    assert [%{id: id}] = Media.list_files(scenario)
    assert id == file.id

    assert {:ok, _} = Media.delete_file(file)
    assert Media.list_files(scenario) == []
    refute File.exists?(disk)
  end

  test "filenames are sanitized against path tricks", %{
    user: user,
    scenario: scenario,
    source: source
  } do
    assert {:ok, file} =
             Media.create_file(
               scenario,
               user,
               attrs(source, %{filename: "../../etc/pass wd?.png"})
             )

    assert file.filename == "pass_wd_.png"
  end

  test "only media content types are accepted", %{
    user: user,
    scenario: scenario,
    source: source
  } do
    assert {:error, changeset} =
             Media.create_file(
               scenario,
               user,
               attrs(source, %{filename: "evil.html", content_type: "text/html"})
             )

    assert %{content_type: [_]} = errors_on(changeset)
  end
end
