defmodule Scenex.DemoScenarioTest do
  use Scenex.DataCase, async: true

  import Scenex.AccountsFixtures

  alias Scenex.{Authoring, DemoScenario}
  alias Scenex.Play.Definition

  test "creates the full CIVITAS scenario for a user, exactly once" do
    user = user_fixture()

    assert {:ok, scenario} = DemoScenario.create(user)
    assert scenario.handle == "CIVITAS"
    assert Authoring.get_user_role(scenario, user) == :owner

    assert length(Authoring.list_value_dimensions(scenario)) == 6
    assert length(Authoring.list_groups(scenario)) == 3

    # The Overall Index is configured (name, keyed formula, bands) so the demo
    # shows the scoreboard gauge out of the box.
    assert scenario.overall_index_name == %{"en" => "Democracy"}
    assert scenario.overall_index_formula =~ "stability"
    assert length(Authoring.list_overall_index_bands(scenario)) == 5

    # Per-participant well_being carries its emoji step scale.
    wb = Enum.find(Authoring.list_value_dimensions(scenario), &(&1.key == "well_being"))
    assert Enum.map(wb.steps, & &1.emoji) == ["🙁", "😐", "🙂", "😀"]

    elements = Authoring.list_timeline_elements(scenario)
    assert Enum.map(elements, & &1.kind) == [:event, :event, :event, :sidequest, :election]

    # The definition loads and seeds a playable board (proof the conditions,
    # effects, and initial values all validated).
    definition = Definition.load(Authoring.get_scenario!(scenario.id))
    assert map_size(definition.groups) == 3
    assert map_size(definition.options) == 31
    assert length(definition.endings) == 4

    # Idempotent per user.
    assert {:error, :already_exists} = DemoScenario.create(user)
    assert length(Authoring.list_scenarios_for_user(user)) == 1
  end
end
