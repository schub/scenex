defmodule Scenex.Authoring do
  @moduledoc """
  The Authoring context (Layer 2) — creating and maintaining scenarios — the authored game definitions.

  Plain CRUD over the definition graph (scenarios, values, groups, timeline elements, options,
  effects, labels), plus authorization. Authorization lives here, not in
  LiveViews: `get_scenario_for_user/2`, `can_edit?/2`, `is_owner?/2`, `get_user_role/2`.

  `owner`/`author` may edit; `viewer` (and anyone, for a `:published` scenario) may
  read. These roles are unrelated to *playing* (Layer 3).
  """

  import Ecto.Query, warn: false

  alias Scenex.Accounts.User
  alias Scenex.Engine.ValueSpec
  alias Scenex.Repo

  alias Scenex.Authoring.{
    DecisionOption,
    TimelineElement,
    Scenario,
    ScenarioMembership,
    Group,
    GroupInitialValue,
    Label,
    OptionEffect,
    ValueDimension
  }

  # ── Games ───────────────────────────────────────────────────────────────

  @doc "Games the user may see: any they're a member of, plus published ones."
  def list_scenarios_for_user(%User{} = user) do
    Repo.all(
      from g in Scenario,
        left_join: m in ScenarioMembership,
        on: m.scenario_id == g.id and m.user_id == ^user.id,
        where: not is_nil(m.id) or g.visibility == :published,
        distinct: true,
        order_by: [desc: g.updated_at]
    )
  end

  def get_scenario!(id), do: Repo.get!(Scenario, id)

  @doc """
  Fetch a scenario the user may access, returning `{scenario, role}` or `nil`.
  Route request reads through this rather than `get_scenario!/1`.
  """
  def get_scenario_for_user(id, user) do
    case Repo.get(Scenario, id) do
      nil ->
        nil

      scenario ->
        case get_user_role(scenario, user) do
          nil -> nil
          role -> {scenario, role}
        end
    end
  end

  @doc "Create a scenario and make its creator the owner, atomically."
  def create_scenario(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:scenario, Scenario.changeset(%Scenario{}, attrs))
    |> Ecto.Multi.insert(:membership, fn %{scenario: scenario} ->
      ScenarioMembership.changeset(%ScenarioMembership{}, %{
        scenario_id: scenario.id,
        user_id: user.id,
        role: :owner
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{scenario: scenario}} -> {:ok, scenario}
      {:error, :scenario, changeset, _} -> {:error, changeset}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def update_scenario(%Scenario{} = scenario, attrs),
    do: scenario |> Scenario.changeset(attrs) |> Repo.update()

  def delete_scenario(%Scenario{} = scenario), do: Repo.delete(scenario)

  def change_scenario(%Scenario{} = scenario, attrs \\ %{}),
    do: Scenario.changeset(scenario, attrs)

  # ── Authorization ───────────────────────────────────────────────────────

  @doc "The user's role on a scenario: `:owner | :author | :viewer | nil`."
  def get_user_role(scenario, user)

  def get_user_role(%Scenario{} = scenario, %User{} = user) do
    membership_role =
      Repo.one(
        from m in ScenarioMembership,
          where: m.scenario_id == ^scenario.id and m.user_id == ^user.id,
          select: m.role
      )

    membership_role || public_role(scenario)
  end

  def get_user_role(%Scenario{} = scenario, nil), do: public_role(scenario)

  defp public_role(%Scenario{visibility: :published}), do: :viewer
  defp public_role(_game), do: nil

  def can_edit?(scenario, user), do: get_user_role(scenario, user) in [:owner, :author]

  def is_owner?(scenario, user), do: get_user_role(scenario, user) == :owner

  # ── Membership ──────────────────────────────────────────────────────────

  def list_members(%Scenario{} = scenario) do
    Repo.all(from m in ScenarioMembership, where: m.scenario_id == ^scenario.id, preload: [:user])
  end

  def add_member(%Scenario{} = scenario, %User{} = user, role) do
    %ScenarioMembership{}
    |> ScenarioMembership.changeset(%{scenario_id: scenario.id, user_id: user.id, role: role})
    |> Repo.insert()
  end

  def remove_member(%ScenarioMembership{} = membership), do: Repo.delete(membership)

  # ── Value dimensions ────────────────────────────────────────────────────

  def list_value_dimensions(%Scenario{} = scenario) do
    Repo.all(from v in ValueDimension, where: v.scenario_id == ^scenario.id, order_by: v.position)
  end

  def get_value_dimension!(id), do: Repo.get!(ValueDimension, id)

  def create_value_dimension(%Scenario{} = scenario, attrs) do
    scenario
    |> Ecto.build_assoc(:value_dimensions)
    |> ValueDimension.changeset(attrs)
    |> Repo.insert()
  end

  def update_value_dimension(%ValueDimension{} = vd, attrs),
    do: vd |> ValueDimension.changeset(attrs) |> Repo.update()

  def delete_value_dimension(%ValueDimension{} = vd), do: Repo.delete(vd)

  def change_value_dimension(%ValueDimension{} = vd, attrs \\ %{}),
    do: ValueDimension.changeset(vd, attrs)

  @doc "Project a value definition into the pure engine's `ValueSpec` (id as key)."
  def to_value_spec(%ValueDimension{} = vd) do
    %ValueSpec{
      key: vd.id,
      aggregation: vd.aggregation,
      min: vd.min,
      max: vd.max,
      input_scope: vd.input_scope
    }
  end

  # ── Groups ──────────────────────────────────────────────────────────────

  def list_groups(%Scenario{} = scenario) do
    Repo.all(from g in Group, where: g.scenario_id == ^scenario.id, order_by: g.position)
  end

  def get_group!(id), do: Repo.get!(Group, id)

  def create_group(%Scenario{} = scenario, attrs) do
    scenario
    |> Ecto.build_assoc(:groups)
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  def update_group(%Group{} = group, attrs),
    do: group |> Group.changeset(attrs) |> Repo.update()

  def delete_group(%Group{} = group), do: Repo.delete(group)

  def change_group(%Group{} = group, attrs \\ %{}), do: Group.changeset(group, attrs)

  # ── Group initial values (upsert) ───────────────────────────────────────

  @doc "Create or update a group's starting value for one value definition."
  def set_group_initial_value(%Group{} = group, %ValueDimension{} = vd, initial) do
    %GroupInitialValue{}
    |> GroupInitialValue.changeset(%{
      group_id: group.id,
      value_dimension_id: vd.id,
      initial: initial
    })
    |> Repo.insert(
      on_conflict: {:replace, [:initial, :updated_at]},
      conflict_target: [:group_id, :value_dimension_id]
    )
  end

  def list_group_initial_values(%Group{} = group) do
    Repo.all(from giv in GroupInitialValue, where: giv.group_id == ^group.id)
  end

  # ── Events ──────────────────────────────────────────────────────────────

  def list_timeline_elements(%Scenario{} = scenario) do
    Repo.all(
      from e in TimelineElement, where: e.scenario_id == ^scenario.id, order_by: e.position
    )
  end

  def get_timeline_element!(id), do: Repo.get!(TimelineElement, id)

  def create_timeline_element(%Scenario{} = scenario, attrs) do
    scenario
    |> Ecto.build_assoc(:timeline_elements)
    |> TimelineElement.changeset(attrs)
    |> Repo.insert()
  end

  def update_timeline_element(%TimelineElement{} = timeline_element, attrs),
    do: timeline_element |> TimelineElement.changeset(attrs) |> Repo.update()

  def delete_timeline_element(%TimelineElement{} = timeline_element),
    do: Repo.delete(timeline_element)

  def change_timeline_element(%TimelineElement{} = timeline_element, attrs \\ %{}),
    do: TimelineElement.changeset(timeline_element, attrs)

  # ── Decision options ────────────────────────────────────────────────────

  def list_decision_options(%TimelineElement{} = timeline_element) do
    Repo.all(
      from o in DecisionOption,
        where: o.timeline_element_id == ^timeline_element.id,
        order_by: [o.group_id, o.position],
        preload: [:labels, :effects]
    )
  end

  def list_decision_options_for_group(%TimelineElement{} = timeline_element, %Group{} = group) do
    Repo.all(
      from o in DecisionOption,
        where: o.timeline_element_id == ^timeline_element.id and o.group_id == ^group.id,
        order_by: o.position
    )
  end

  def get_decision_option!(id),
    do: Repo.get!(DecisionOption, id) |> Repo.preload([:labels, :effects])

  def create_decision_option(%TimelineElement{} = timeline_element, %Group{} = group, attrs) do
    timeline_element
    |> Ecto.build_assoc(:decision_options, group_id: group.id)
    |> DecisionOption.changeset(attrs)
    |> Repo.insert()
  end

  def update_decision_option(%DecisionOption{} = option, attrs),
    do: option |> DecisionOption.changeset(attrs) |> Repo.update()

  def delete_decision_option(%DecisionOption{} = option), do: Repo.delete(option)

  def change_decision_option(%DecisionOption{} = option, attrs \\ %{}),
    do: DecisionOption.changeset(option, attrs)

  @doc "Replace an option's labels (many-to-many)."
  def set_option_labels(%DecisionOption{} = option, labels) when is_list(labels) do
    option
    |> Repo.preload(:labels)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:labels, labels)
    |> Repo.update()
  end

  # ── Option effects (upsert) ─────────────────────────────────────────────

  @doc "Create or update the delta an option applies to one value."
  def set_option_effect(%DecisionOption{} = option, %ValueDimension{} = vd, delta) do
    %OptionEffect{}
    |> OptionEffect.changeset(%{
      decision_option_id: option.id,
      value_dimension_id: vd.id,
      delta: delta
    })
    |> Repo.insert(
      on_conflict: {:replace, [:delta, :updated_at]},
      conflict_target: [:decision_option_id, :value_dimension_id]
    )
  end

  def list_option_effects(%DecisionOption{} = option) do
    Repo.all(from oe in OptionEffect, where: oe.decision_option_id == ^option.id)
  end

  # ── Labels ──────────────────────────────────────────────────────────────

  def list_labels(%Scenario{} = scenario) do
    Repo.all(from l in Label, where: l.scenario_id == ^scenario.id, order_by: l.position)
  end

  def get_label!(id), do: Repo.get!(Label, id)

  def create_label(%Scenario{} = scenario, attrs) do
    scenario
    |> Ecto.build_assoc(:labels)
    |> Label.changeset(attrs)
    |> Repo.insert()
  end

  def update_label(%Label{} = label, attrs),
    do: label |> Label.changeset(attrs) |> Repo.update()

  def delete_label(%Label{} = label), do: Repo.delete(label)

  def change_label(%Label{} = label, attrs \\ %{}), do: Label.changeset(label, attrs)
end
