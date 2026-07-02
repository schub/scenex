defmodule Scenex.AuthoringTest do
  use Scenex.DataCase, async: true

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring
  alias Scenex.Engine.{Sim, ValueSpec}

  describe "create_game/2 and authorization" do
    test "creates the game and makes the creator the owner" do
      user = user_fixture()
      assert {:ok, game} = Authoring.create_game(user, %{handle: "Lux", name: %{"en" => "Lux"}})

      assert Authoring.get_user_role(game, user) == :owner
      assert Authoring.is_owner?(game, user)
      assert Authoring.can_edit?(game, user)
    end

    test "requires a non-blank localized name" do
      user = user_fixture()
      assert {:error, changeset} = Authoring.create_game(user, %{name: %{"en" => "  "}})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "a non-member has no role on a draft game and cannot fetch it" do
      owner = user_fixture()
      other = user_fixture()
      game = game_fixture(owner)

      assert Authoring.get_user_role(game, other) == nil
      refute Authoring.can_edit?(game, other)
      assert Authoring.get_game_for_user(game.id, other) == nil
    end

    test "anyone gets :viewer on a published game" do
      owner = user_fixture()
      other = user_fixture()
      game = game_fixture(owner, visibility: :published)

      assert Authoring.get_user_role(game, other) == :viewer
      assert Authoring.get_user_role(game, nil) == :viewer
      refute Authoring.can_edit?(game, other)
      assert {%{}, :viewer} = Authoring.get_game_for_user(game.id, other)
    end

    test "list_games_for_user returns member and published games" do
      owner = user_fixture()
      other = user_fixture()
      mine = game_fixture(owner)
      published = game_fixture(other, visibility: :published)
      _hidden = game_fixture(other)

      ids = owner |> Authoring.list_games_for_user() |> Enum.map(& &1.id) |> MapSet.new()
      assert MapSet.member?(ids, mine.id)
      assert MapSet.member?(ids, published.id)
    end
  end

  describe "value definitions" do
    setup do
      user = user_fixture()
      %{game: game_fixture(user)}
    end

    test "validates the aggregation formula", %{game: game} do
      assert {:error, changeset} =
               Authoring.create_value_definition(game, %{
                 key: "risk",
                 name: %{"en" => "Risk"},
                 aggregation: "bogus("
               })

      assert %{aggregation: [_]} = errors_on(changeset)
    end

    test "validates the key slug and uniqueness per game", %{game: game} do
      assert {:error, cs} =
               Authoring.create_value_definition(game, %{
                 key: "Not A Slug",
                 name: %{"en" => "X"},
                 aggregation: "avg"
               })

      assert %{key: [_]} = errors_on(cs)

      value_definition_fixture(game, key: "stability")

      assert {:error, cs2} =
               Authoring.create_value_definition(game, %{
                 key: "stability",
                 name: %{"en" => "Dup"},
                 aggregation: "avg"
               })

      assert %{key: [_]} = errors_on(cs2)
    end

    test "rejects min greater than max", %{game: game} do
      assert {:error, cs} =
               Authoring.create_value_definition(game, %{
                 key: "risk",
                 name: %{"en" => "Risk"},
                 aggregation: "max",
                 min: 100.0,
                 max: 0.0
               })

      assert %{max: [_]} = errors_on(cs)
    end

    test "projects into an engine ValueSpec", %{game: game} do
      vd =
        value_definition_fixture(game, key: "stability", aggregation: "avg", min: 0.0, max: 100.0)

      spec = Authoring.to_value_spec(vd)
      assert %ValueSpec{} = spec
      assert spec.key == vd.id
      assert spec.aggregation == "avg"
      assert spec.min == 0.0
      assert spec.max == 100.0
      assert spec.input_scope == :per_group
    end
  end

  describe "handle uniqueness" do
    test "two groups in the same game can't share a handle" do
      user = user_fixture()
      game = game_fixture(user)

      assert {:ok, _} = Authoring.create_group(game, %{handle: "Gov", name: %{"en" => "A"}})

      assert {:error, cs} = Authoring.create_group(game, %{handle: "Gov", name: %{"en" => "B"}})
      assert %{handle: ["is already used in this game"]} = errors_on(cs)
    end

    test "the same handle is allowed in a different game" do
      user = user_fixture()
      game1 = game_fixture(user)
      game2 = game_fixture(user)

      assert {:ok, _} = Authoring.create_group(game1, %{handle: "Gov", name: %{"en" => "A"}})
      assert {:ok, _} = Authoring.create_group(game2, %{handle: "Gov", name: %{"en" => "B"}})
    end
  end

  describe "group initial values (upsert)" do
    test "creates then updates by (group, value_definition)" do
      user = user_fixture()
      game = game_fixture(user)
      group = group_fixture(game)
      vd = value_definition_fixture(game)

      assert {:ok, giv} = Authoring.set_group_initial_value(group, vd, 60.0)
      assert giv.initial == 60.0

      assert {:ok, _} = Authoring.set_group_initial_value(group, vd, 42.0)
      assert [only] = Authoring.list_group_initial_values(group)
      assert only.initial == 42.0
    end
  end

  describe "decision options, effects and labels" do
    setup do
      user = user_fixture()
      game = game_fixture(user)
      group = group_fixture(game)
      event = event_fixture(game)
      vd = value_definition_fixture(game)
      %{game: game, group: group, event: event, vd: vd}
    end

    test "an option belongs to an event and a group", %{event: event, group: group} do
      assert {:ok, option} =
               Authoring.create_decision_option(event, group, %{
                 handle: "Ration",
                 text: %{"en" => "Ration"}
               })

      assert option.event_id == event.id
      assert option.group_id == group.id
    end

    test "set_option_effect upserts the delta", %{event: event, group: group, vd: vd} do
      option = decision_option_fixture(event, group)

      assert {:ok, _} = Authoring.set_option_effect(option, vd, 10.0)
      assert {:ok, _} = Authoring.set_option_effect(option, vd, -5.0)

      assert [effect] = Authoring.list_option_effects(option)
      assert effect.delta == -5.0
    end

    test "set_option_labels assigns many labels", %{game: game, event: event, group: group} do
      option = decision_option_fixture(event, group)
      l1 = label_fixture(game, name: %{"en" => "Aggressive"}, color: :error)
      l2 = label_fixture(game, name: %{"en" => "Costly"}, color: :warning)

      assert {:ok, option} = Authoring.set_option_labels(option, [l1, l2])
      assert option.labels |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([l1.id, l2.id])
    end
  end

  test "an authored value + group + effect flows through the engine end to end" do
    user = user_fixture()
    game = game_fixture(user)
    gov = group_fixture(game, name: %{"en" => "Government"})
    media = group_fixture(game, name: %{"en" => "Media"})

    stability =
      value_definition_fixture(game, key: "stability", aggregation: "avg", min: 0.0, max: 100.0)

    Authoring.set_group_initial_value(gov, stability, 60.0)
    Authoring.set_group_initial_value(media, stability, 40.0)

    spec = Authoring.to_value_spec(stability)
    sim = Sim.new([spec], [gov.id, media.id], %{spec.key => %{gov.id => 60.0, media.id => 40.0}})

    assert Sim.globals(sim)[spec.key] == 50.0

    sim = Sim.apply_effect(sim, spec.key, gov.id, -20.0)
    assert Sim.globals(sim)[spec.key] == 40.0
  end
end
