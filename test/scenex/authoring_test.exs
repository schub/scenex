defmodule Scenex.AuthoringTest do
  use Scenex.DataCase, async: true

  import Scenex.AccountsFixtures
  import Scenex.AuthoringFixtures

  alias Scenex.Authoring
  alias Scenex.Engine.{Sim, ValueSpec}

  describe "create_scenario/2 and authorization" do
    test "creates the scenario and makes the creator the owner" do
      user = user_fixture()

      assert {:ok, scenario} =
               Authoring.create_scenario(user, %{handle: "Lux", name: %{"en" => "Lux"}})

      assert Authoring.get_user_role(scenario, user) == :owner
      assert Authoring.is_owner?(scenario, user)
      assert Authoring.can_edit?(scenario, user)
    end

    test "requires a non-blank localized name" do
      user = user_fixture()
      assert {:error, changeset} = Authoring.create_scenario(user, %{name: %{"en" => "  "}})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "a non-member has no role on a draft scenario and cannot fetch it" do
      owner = user_fixture()
      other = user_fixture()
      scenario = scenario_fixture(owner)

      assert Authoring.get_user_role(scenario, other) == nil
      refute Authoring.can_edit?(scenario, other)
      assert Authoring.get_scenario_for_user(scenario.id, other) == nil
    end

    test "anyone gets :viewer on a published scenario" do
      owner = user_fixture()
      other = user_fixture()
      scenario = scenario_fixture(owner, visibility: :published)

      assert Authoring.get_user_role(scenario, other) == :viewer
      assert Authoring.get_user_role(scenario, nil) == :viewer
      refute Authoring.can_edit?(scenario, other)
      assert {%{}, :viewer} = Authoring.get_scenario_for_user(scenario.id, other)
    end

    test "list_scenarios_for_user returns member and published scenarios" do
      owner = user_fixture()
      other = user_fixture()
      mine = scenario_fixture(owner)
      published = scenario_fixture(other, visibility: :published)
      _hidden = scenario_fixture(other)

      ids = owner |> Authoring.list_scenarios_for_user() |> Enum.map(& &1.id) |> MapSet.new()
      assert MapSet.member?(ids, mine.id)
      assert MapSet.member?(ids, published.id)
    end
  end

  describe "value definitions" do
    setup do
      user = user_fixture()
      %{scenario: scenario_fixture(user)}
    end

    test "validates the aggregation formula", %{scenario: scenario} do
      assert {:error, changeset} =
               Authoring.create_value_dimension(scenario, %{
                 key: "risk",
                 name: %{"en" => "Risk"},
                 aggregation: "bogus("
               })

      assert %{aggregation: [_]} = errors_on(changeset)
    end

    test "validates the key slug and uniqueness per scenario", %{scenario: scenario} do
      assert {:error, cs} =
               Authoring.create_value_dimension(scenario, %{
                 key: "Not A Slug",
                 name: %{"en" => "X"},
                 aggregation: "avg"
               })

      assert %{key: [_]} = errors_on(cs)

      value_dimension_fixture(scenario, key: "stability")

      assert {:error, cs2} =
               Authoring.create_value_dimension(scenario, %{
                 key: "stability",
                 name: %{"en" => "Dup"},
                 aggregation: "avg"
               })

      assert %{key: [_]} = errors_on(cs2)
    end

    test "rejects min greater than max", %{scenario: scenario} do
      assert {:error, cs} =
               Authoring.create_value_dimension(scenario, %{
                 key: "risk",
                 name: %{"en" => "Risk"},
                 aggregation: "max",
                 min: 100.0,
                 max: 0.0
               })

      assert %{max: [_]} = errors_on(cs)
    end

    test "drops bounds for per-participant values", %{scenario: scenario} do
      assert {:ok, vd} =
               Authoring.create_value_dimension(scenario, %{
                 key: "wellbeing",
                 name: %{"en" => "Well-being"},
                 aggregation: "avg",
                 input_scope: :per_participant,
                 min: 0.0,
                 max: 100.0,
                 default_value: 50.0
               })

      assert vd.min == nil
      assert vd.max == nil
      assert vd.default_value == nil
    end

    test "projects into an engine ValueSpec", %{scenario: scenario} do
      vd =
        value_dimension_fixture(scenario,
          key: "stability",
          aggregation: "avg",
          min: 0.0,
          max: 100.0
        )

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
    test "two groups in the same scenario can't share a handle" do
      user = user_fixture()
      scenario = scenario_fixture(user)

      assert {:ok, _} = Authoring.create_group(scenario, %{handle: "Gov", name: %{"en" => "A"}})

      assert {:error, cs} =
               Authoring.create_group(scenario, %{handle: "Gov", name: %{"en" => "B"}})

      assert %{handle: ["is already used in this scenario"]} = errors_on(cs)
    end

    test "the same handle is allowed in a different scenario" do
      user = user_fixture()
      game1 = scenario_fixture(user)
      game2 = scenario_fixture(user)

      assert {:ok, _} = Authoring.create_group(game1, %{handle: "Gov", name: %{"en" => "A"}})
      assert {:ok, _} = Authoring.create_group(game2, %{handle: "Gov", name: %{"en" => "B"}})
    end
  end

  describe "group initial values (upsert)" do
    test "creates then updates by (group, value_dimension)" do
      user = user_fixture()
      scenario = scenario_fixture(user)
      group = group_fixture(scenario)
      vd = value_dimension_fixture(scenario)

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
      scenario = scenario_fixture(user)
      group = group_fixture(scenario)
      timeline_element = timeline_element_fixture(scenario)
      vd = value_dimension_fixture(scenario)
      %{scenario: scenario, group: group, timeline_element: timeline_element, vd: vd}
    end

    test "an option belongs to a timeline element and a group", %{
      timeline_element: timeline_element,
      group: group
    } do
      assert {:ok, option} =
               Authoring.create_decision_option(timeline_element, group, %{
                 handle: "Ration",
                 text: %{"en" => "Ration"}
               })

      assert option.timeline_element_id == timeline_element.id
      assert option.group_id == group.id
    end

    test "set_option_effect upserts the delta", %{
      timeline_element: timeline_element,
      group: group,
      vd: vd
    } do
      option = decision_option_fixture(timeline_element, group)

      assert {:ok, _} = Authoring.set_option_effect(option, vd, 10.0)
      assert {:ok, _} = Authoring.set_option_effect(option, vd, -5.0)

      assert [effect] = Authoring.list_option_effects(option)
      assert effect.delta == -5.0
    end

    test "set_option_labels assigns many labels", %{
      scenario: scenario,
      timeline_element: timeline_element,
      group: group
    } do
      option = decision_option_fixture(timeline_element, group)
      l1 = label_fixture(scenario, name: %{"en" => "Aggressive"}, color: :error)
      l2 = label_fixture(scenario, name: %{"en" => "Costly"}, color: :warning)

      assert {:ok, option} = Authoring.set_option_labels(option, [l1, l2])
      assert option.labels |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([l1.id, l2.id])
    end
  end

  test "an authored value + group + effect flows through the engine end to end" do
    user = user_fixture()
    scenario = scenario_fixture(user)
    gov = group_fixture(scenario, name: %{"en" => "Government"})
    media = group_fixture(scenario, name: %{"en" => "Media"})

    stability =
      value_dimension_fixture(scenario,
        key: "stability",
        aggregation: "avg",
        min: 0.0,
        max: 100.0
      )

    Authoring.set_group_initial_value(gov, stability, 60.0)
    Authoring.set_group_initial_value(media, stability, 40.0)

    spec = Authoring.to_value_spec(stability)
    sim = Sim.new([spec], [gov.id, media.id], %{spec.key => %{gov.id => 60.0, media.id => 40.0}})

    assert Sim.globals(sim)[spec.key] == 50.0

    sim = Sim.apply_effect(sim, spec.key, gov.id, -20.0)
    assert Sim.globals(sim)[spec.key] == 40.0
  end
end
