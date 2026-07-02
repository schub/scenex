defmodule Scenex.AuthoringFixtures do
  @moduledoc "Test fixtures for the Authoring context."

  alias Scenex.Authoring

  def game_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{handle: "Test Game", name: %{"en" => "Test Game"}, source_locale: "en"})

    {:ok, game} = Authoring.create_game(user, attrs)
    game
  end

  def value_definition_fixture(game, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        key: "stability",
        name: %{"en" => "Stability"},
        aggregation: "avg",
        min: 0.0,
        max: 100.0
      })

    {:ok, vd} = Authoring.create_value_definition(game, attrs)
    vd
  end

  def group_fixture(game, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: "Government", name: %{"en" => "Government"}})
    {:ok, group} = Authoring.create_group(game, attrs)
    group
  end

  def event_fixture(game, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: "Blackout", title: %{"en" => "Blackout"}})
    {:ok, event} = Authoring.create_event(game, attrs)
    event
  end

  def decision_option_fixture(event, group, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{handle: "Ration power", text: %{"en" => "Ration power"}})
    {:ok, option} = Authoring.create_decision_option(event, group, attrs)
    option
  end

  def label_fixture(game, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{handle: "Aggressive", name: %{"en" => "Aggressive"}, color: :error})

    {:ok, label} = Authoring.create_label(game, attrs)
    label
  end
end
