defmodule Scenex.Authoring.CopyTest do
  use Scenex.DataCase, async: true

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring
  alias Scenex.Media
  alias Scenex.Media.Storage.Local
  alias Scenex.Repo

  setup do
    owner = user_fixture()

    scenario =
      scenario_fixture(owner, key: "Original", name: %{"en" => "Original", "de" => "Original DE"})

    stability =
      value_dimension_fixture(scenario, %{
        key: "stability",
        name: %{"en" => "Stability", "de" => "Stabilität"},
        min: 0.0,
        max: 10.0
      })

    Authoring.create_value_dimension_step(stability, %{
      position: 1,
      emoji: "😐",
      name: %{"en" => "OK"}
    })

    gov = group_fixture(scenario, key: "gov", name: %{"en" => "Government"})
    media_group = group_fixture(scenario, key: "media", name: %{"en" => "Media"})
    Authoring.set_group_initial_value(gov, stability, 5.0)

    archived = group_fixture(scenario, key: "old", name: %{"en" => "Old"})

    {:ok, _} =
      archived |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update()

    label = label_fixture(scenario, key: "bold", name: %{"en" => "Bold"})

    event =
      timeline_element_fixture(scenario,
        key: "Blackout",
        title: %{"en" => "Blackout"},
        description: %{"en" => "See ![img](/media/PLACEHOLDER/poster.png)"},
        deadline_seconds: 300
      )

    {:ok, option} =
      Authoring.create_decision_option(event, gov, %{
        key: "Crack",
        name: %{"en" => "Crack", "de" => "Knacken"},
        is_default: true
      })

    Authoring.set_option_effect(option, stability, 2.0)
    Authoring.set_option_labels(option, [label])

    # Option aimed at the archived group — must not come along.
    Authoring.create_decision_option(event, archived, %{key: "Gone", name: %{"en" => "Gone"}})

    {:ok, ending} =
      Authoring.create_ending(scenario, %{
        key: "hold",
        title: %{"en" => "We hold"},
        condition: "global(stability) >= 5",
        priority: 1
      })

    {:ok, page} =
      Authoring.create_page(scenario, %{
        key: "title",
        content: %{"en" => "![poster](/media/PLACEHOLDER/poster.png)"}
      })

    {:ok, band} =
      Authoring.create_overall_index_band(scenario, %{name: %{"en" => "Good"}, position: 1})

    {:ok, _} =
      Authoring.update_scenario(scenario, %{
        overall_index_formula: "stability",
        overall_index_min: 0.0,
        overall_index_max: 10.0
      })

    source = Path.join(System.tmp_dir!(), "copy_src_#{System.unique_integer([:positive])}")
    File.write!(source, "poster bytes")
    on_exit(fn -> File.rm(source) end)

    {:ok, file} =
      Media.create_file(scenario, owner, %{
        path: source,
        filename: "poster.png",
        content_type: "image/png",
        size: 12
      })

    # Point the markdown at the real media id.
    {:ok, event} =
      Authoring.update_timeline_element(event, %{
        description: %{"en" => "See ![img](#{Media.public_path(file)})"}
      })

    {:ok, page} =
      Authoring.update_page(page, %{content: %{"en" => "![poster](#{Media.public_path(file)})"}})

    %{
      owner: owner,
      scenario: Authoring.get_scenario!(scenario.id),
      stability: stability,
      gov: gov,
      media_group: media_group,
      archived: archived,
      label: label,
      event: event,
      option: option,
      ending: ending,
      page: page,
      band: band,
      media_file: file
    }
  end

  test "copies the authored graph under new ids; the copier owns a draft", ctx do
    viewer = user_fixture()
    Authoring.add_member(ctx.scenario, viewer, :viewer)

    assert {:ok, copy} = Authoring.copy_scenario(viewer, ctx.scenario)

    assert copy.id != ctx.scenario.id
    assert copy.key == "Original (copy)"
    assert copy.visibility == :draft
    assert copy.name == %{"en" => "Original", "de" => "Original DE"}
    assert copy.overall_index_formula == "stability"
    assert Authoring.is_owner?(copy, viewer)
    refute Authoring.is_owner?(copy, ctx.owner)

    # Values + steps
    [vd] = Authoring.list_value_dimensions(copy)
    assert vd.id != ctx.stability.id
    assert vd.key == "stability"
    assert vd.name["de"] == "Stabilität"
    assert [%{emoji: "😐"}] = Authoring.list_value_dimension_steps(vd)

    # Active groups only; archived stays behind
    groups = Authoring.list_groups(copy)
    assert Enum.map(groups, & &1.key) |> Enum.sort() == ["gov", "media"]
    gov = Enum.find(groups, &(&1.key == "gov"))
    assert [%{initial: 5.0, value_dimension_id: vd_id}] = Authoring.list_group_initial_values(gov)
    assert vd_id == vd.id

    # Labels, endings, pages, bands
    assert [%{key: "bold"}] = Authoring.list_labels(copy)
    assert [%{key: "hold", condition: "global(stability) >= 5"}] = Authoring.list_endings(copy)
    assert [%{key: "title"}] = Authoring.list_pages(copy)
    assert [%{name: %{"en" => "Good"}}] = Authoring.list_overall_index_bands(copy)

    # Timeline: one option (not the archived group's), with effect + label
    [element] = Authoring.list_timeline_elements(copy)
    assert element.key == "Blackout"
    assert element.deadline_seconds == 300
    [option] = Authoring.list_decision_options(element)
    assert option.key == "Crack"
    assert option.group_id == gov.id
    assert option.is_default
    assert [%{key: "bold"}] = option.labels
    assert [%{delta: 2.0}] = option.effects
  end

  test "copies media bytes and rewrites /media/<id>/ links in content", ctx do
    assert {:ok, copy} = Authoring.copy_scenario(ctx.owner, ctx.scenario)

    [file] = Media.list_files(copy)
    assert file.id != ctx.media_file.id
    assert file.filename == "poster.png"
    assert File.read!(Local.path(Media.key(file))) == "poster bytes"

    [element] = Authoring.list_timeline_elements(copy)
    assert element.description["en"] =~ "/media/#{file.id}/poster.png"
    refute element.description["en"] =~ ctx.media_file.id

    [page] = Authoring.list_pages(copy)
    assert page.content["en"] =~ "/media/#{file.id}/poster.png"
  end

  test "locales: keeps only the chosen ones (and always the source locale)", ctx do
    assert {:ok, copy} = Authoring.copy_scenario(ctx.owner, ctx.scenario, locales: ["de"])

    assert copy.name == %{"en" => "Original", "de" => "Original DE"}
    [vd] = Authoring.list_value_dimensions(copy)
    assert vd.name == %{"en" => "Stability", "de" => "Stabilität"}

    [element] = Authoring.list_timeline_elements(copy)
    [option] = Authoring.list_decision_options(element)
    # "en" kept as source; "de" requested; nothing else existed
    assert option.name == %{"en" => "Crack", "de" => "Knacken"}
  end

  test "anyone with read access may copy; others may not", ctx do
    stranger = user_fixture()
    assert {:error, :unauthorized} = Authoring.copy_scenario(stranger, ctx.scenario)

    {:ok, _} = Authoring.update_scenario(ctx.scenario, %{visibility: :published})
    scenario = Authoring.get_scenario!(ctx.scenario.id)
    assert {:ok, copy} = Authoring.copy_scenario(stranger, scenario)
    assert Authoring.is_owner?(copy, stranger)
  end

  test "does not copy sessions or memberships of the original", ctx do
    other = user_fixture()
    Authoring.add_member(ctx.scenario, other, :author)

    assert {:ok, copy} = Authoring.copy_scenario(ctx.owner, ctx.scenario)
    assert Authoring.list_members(copy) |> Enum.map(& &1.user_id) == [ctx.owner.id]
  end
end
