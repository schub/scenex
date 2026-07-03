defmodule Scenex.AuthoringFixtures do
  @moduledoc "Test fixtures for the Authoring context."

  alias Scenex.Authoring

  def scenario_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        handle: "Test Scenario",
        name: %{"en" => "Test Scenario"},
        source_locale: "en"
      })

    {:ok, scenario} = Authoring.create_scenario(user, attrs)
    scenario
  end

  def value_dimension_fixture(scenario, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        key: "stability",
        name: %{"en" => "Stability"},
        aggregation: "avg",
        min: 0.0,
        max: 100.0
      })

    {:ok, vd} = Authoring.create_value_dimension(scenario, attrs)
    vd
  end

  def group_fixture(scenario, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: unique("group"), name: %{"en" => "Government"}})
    {:ok, group} = Authoring.create_group(scenario, attrs)
    group
  end

  def timeline_element_fixture(scenario, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: unique("timeline_element"), title: %{"en" => "Blackout"}})
    {:ok, timeline_element} = Authoring.create_timeline_element(scenario, attrs)
    timeline_element
  end

  def decision_option_fixture(timeline_element, group, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: unique("option"), text: %{"en" => "Ration power"}})
    {:ok, option} = Authoring.create_decision_option(timeline_element, group, attrs)
    option
  end

  def label_fixture(scenario, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{handle: unique("label"), name: %{"en" => "Aggressive"}, color: :error})

    {:ok, label} = Authoring.create_label(scenario, attrs)
    label
  end

  # Handles must be unique within their scope; keep default fixtures distinct.
  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
