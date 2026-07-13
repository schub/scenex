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
    Ending,
    TimelineElement,
    Scenario,
    ScenarioInvitation,
    ScenarioMembership,
    Group,
    GroupInitialValue,
    Label,
    OptionEffect,
    ValueDimension
  }

  # ── Scenarios ───────────────────────────────────────────────────────────

  @doc "Scenarios the user may see: any they're a member of, plus published ones."
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

  # ── Invitations ─────────────────────────────────────────────────────────
  #
  # Public registration is closed; inviting someone by email is how new
  # accounts come into existence. Two paths:
  #
  #   * email belongs to an existing user  → membership is added right away
  #   * email is unknown                   → a ScenarioInvitation is stored and
  #     an acceptance link emailed; accepting creates the account (password
  #     required) and the membership in one step.

  @doc """
  Invite `email` to `scenario` with `role` (`:author` or `:viewer`).

  Returns:

    * `{:ok, :member_added}` — the email already had an account; membership
      added and a notification email sent.
    * `{:ok, :invitation_sent}` — no account yet; invitation stored and an
      acceptance link emailed.
    * `{:error, :already_member}` — the user already has a role on the scenario.
    * `{:error, changeset}` — invalid email or a still-pending invitation.

  `invite_url_fun` receives the encoded token and returns the acceptance URL.
  """
  def invite_member(%Scenario{} = scenario, %User{} = inviter, email, role, invite_url_fun)
      when role in [:author, :viewer] and is_function(invite_url_fun, 1) do
    email = email |> to_string() |> String.trim()

    case Scenex.Accounts.get_user_by_email(email) do
      %User{} = user ->
        case add_member(scenario, user, role) do
          {:ok, _membership} ->
            Scenex.Accounts.UserNotifier.deliver_added_to_scenario(
              user,
              scenario_display_name(scenario),
              role
            )

            {:ok, :member_added}

          {:error, _changeset} ->
            {:error, :already_member}
        end

      nil ->
        {encoded_token, changeset} = ScenarioInvitation.build(scenario, inviter, email, role)

        # Re-inviting the same email replaces the old invitation (fresh token).
        Repo.delete_all(
          from i in ScenarioInvitation,
            where: i.scenario_id == ^scenario.id and i.email == ^email
        )

        with {:ok, invitation} <- Repo.insert(changeset) do
          Scenex.Accounts.UserNotifier.deliver_scenario_invitation(
            invitation.email,
            scenario_display_name(scenario),
            role,
            invite_url_fun.(encoded_token)
          )

          {:ok, :invitation_sent}
        end
    end
  end

  def list_pending_invitations(%Scenario{} = scenario) do
    Repo.all(
      from i in ScenarioInvitation,
        where: i.scenario_id == ^scenario.id,
        order_by: [desc: i.inserted_at]
    )
  end

  def revoke_invitation(%ScenarioInvitation{} = invitation), do: Repo.delete(invitation)

  @doc "Resolve an encoded invite token to a valid invitation (scenario preloaded), or nil."
  def get_invitation_by_token(encoded_token) do
    with {:ok, query} <- ScenarioInvitation.verify_token_query(encoded_token) do
      Repo.one(query)
    else
      :error -> nil
    end
  end

  @doc """
  Accept an invitation by creating a new account with a password.

  Runs in a transaction: registers a confirmed user from the invitation's
  email + the given password params, adds the membership, and deletes the
  invitation. Returns `{:ok, user}` or `{:error, changeset}`.

  If an account for the email appeared after the invite was sent, no account
  is created; the membership is added and `{:ok, :existing_user}` returned —
  the caller should send the person to the login page.
  """
  def accept_invitation(%ScenarioInvitation{} = invitation, password_params) do
    invitation = Repo.preload(invitation, :scenario)

    case Scenex.Accounts.get_user_by_email(invitation.email) do
      %User{} = user ->
        Repo.transact(fn ->
          _ = add_member(invitation.scenario, user, invitation.role)
          {:ok, _} = Repo.delete(invitation)
          {:ok, :existing_user}
        end)

      nil ->
        Repo.transact(fn ->
          with {:ok, user} <-
                 Scenex.Accounts.register_invited_user(invitation.email, password_params),
               {:ok, _membership} <- add_member(invitation.scenario, user, invitation.role),
               {:ok, _} <- Repo.delete(invitation) do
            {:ok, user}
          end
        end)
    end
  end

  defp scenario_display_name(%Scenario{} = scenario) do
    Scenex.I18n.t!(scenario.name, scenario.source_locale, default: scenario.handle)
  end

  # ── Value dimensions ────────────────────────────────────────────────────

  def list_value_dimensions(%Scenario{} = scenario) do
    Repo.all(from v in ValueDimension, where: v.scenario_id == ^scenario.id, order_by: v.position)
  end

  def get_value_dimension!(id), do: Repo.get!(ValueDimension, id)

  @doc "Fetch a value dimension **within** `scenario`, or nil. Use for request-scoped reads."
  def get_value_dimension(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id),
      do: Repo.get_by(ValueDimension, id: uuid, scenario_id: scenario.id)
  end

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

  @doc "Fetch a group **within** `scenario`, or nil. Use for request-scoped reads."
  def get_group(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id), do: Repo.get_by(Group, id: uuid, scenario_id: scenario.id)
  end

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

  @doc "Fetch a timeline element **within** `scenario`, or nil. Use for request-scoped reads."
  def get_timeline_element(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id),
      do: Repo.get_by(TimelineElement, id: uuid, scenario_id: scenario.id)
  end

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

  @doc """
  Fetch a decision option **within** `scenario` (joined through its timeline
  element), labels and effects preloaded, or nil. Use for request-scoped reads.
  """
  def get_decision_option(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id) do
      Repo.one(
        from o in DecisionOption,
          join: e in TimelineElement,
          on: e.id == o.timeline_element_id,
          where: o.id == ^uuid and e.scenario_id == ^scenario.id,
          preload: [:labels, :effects]
      )
    end
  end

  @doc """
  Create an option on a timeline element. `group` is the deciding group for
  event-kind elements and `nil` for elections and sidequests (validated by the
  element's kind).
  """
  def create_decision_option(%TimelineElement{} = timeline_element, group, attrs) do
    timeline_element
    |> Ecto.build_assoc(:decision_options, group_id: group && group.id)
    |> DecisionOption.changeset(attrs, option_opts(timeline_element))
    |> Repo.insert()
  end

  def update_decision_option(%DecisionOption{} = option, attrs) do
    element =
      case option.timeline_element do
        %TimelineElement{} = loaded -> loaded
        _not_loaded -> Repo.get!(TimelineElement, option.timeline_element_id)
      end

    option |> DecisionOption.changeset(attrs, option_opts(element)) |> Repo.update()
  end

  def delete_decision_option(%DecisionOption{} = option), do: Repo.delete(option)

  def change_decision_option(option, attrs \\ %{}, opts \\ [])

  def change_decision_option(%DecisionOption{} = option, attrs, %TimelineElement{} = element),
    do: DecisionOption.changeset(option, attrs, option_opts(element))

  def change_decision_option(%DecisionOption{} = option, attrs, opts),
    do: DecisionOption.changeset(option, attrs, opts)

  # Kind + known value keys for the option changeset's validations.
  defp option_opts(%TimelineElement{} = element),
    do: [kind: element.kind, value_keys: value_keys(element.scenario_id)]

  defp value_keys(scenario_id) do
    Repo.all(from v in ValueDimension, where: v.scenario_id == ^scenario_id, select: v.key)
  end

  @doc "Replace an option's labels (many-to-many)."
  def set_option_labels(%DecisionOption{} = option, labels) when is_list(labels) do
    option
    |> Repo.preload(:labels)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:labels, labels)
    |> Repo.update()
  end

  # ── Option effects (upsert) ─────────────────────────────────────────────

  @doc """
  Create or update the delta an option applies to one value.

  `target_group` is the outcome-matrix dimension: `nil` targets the deciding
  group (event options); a `%Group{}` targets that group explicitly (election
  and sidequest options).
  """
  def set_option_effect(option, vd, target_group \\ nil, delta)

  def set_option_effect(%DecisionOption{} = option, %ValueDimension{} = vd, target_group, delta)
      when is_struct(target_group, Group) or is_nil(target_group) do
    group_id = target_group && target_group.id

    attrs = %{
      decision_option_id: option.id,
      value_dimension_id: vd.id,
      group_id: group_id,
      delta: delta
    }

    case Repo.one(effect_cell_query(option.id, vd.id, group_id)) do
      nil -> %OptionEffect{} |> OptionEffect.changeset(attrs) |> Repo.insert()
      effect -> effect |> OptionEffect.changeset(%{delta: delta}) |> Repo.update()
    end
  end

  defp effect_cell_query(option_id, vd_id, group_id) do
    query =
      from oe in OptionEffect,
        where: oe.decision_option_id == ^option_id and oe.value_dimension_id == ^vd_id

    if group_id,
      do: where(query, [oe], oe.group_id == ^group_id),
      else: where(query, [oe], is_nil(oe.group_id))
  end

  @doc "Remove one effect cell (option × value × target group)."
  def delete_option_effect(
        %DecisionOption{} = option,
        %ValueDimension{} = vd,
        target_group \\ nil
      ) do
    option.id
    |> effect_cell_query(vd.id, target_group && target_group.id)
    |> Repo.delete_all()

    :ok
  end

  def list_option_effects(%DecisionOption{} = option) do
    Repo.all(from oe in OptionEffect, where: oe.decision_option_id == ^option.id)
  end

  # ── Labels ──────────────────────────────────────────────────────────────

  def list_labels(%Scenario{} = scenario) do
    Repo.all(from l in Label, where: l.scenario_id == ^scenario.id, order_by: l.position)
  end

  def get_label!(id), do: Repo.get!(Label, id)

  @doc "Fetch a label **within** `scenario`, or nil. Use for request-scoped reads."
  def get_label(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id), do: Repo.get_by(Label, id: uuid, scenario_id: scenario.id)
  end

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

  # ── Endings ─────────────────────────────────────────────────────────────

  def list_endings(%Scenario{} = scenario) do
    Repo.all(
      from e in Ending,
        where: e.scenario_id == ^scenario.id,
        order_by: [desc: e.priority, asc: e.handle]
    )
  end

  def get_ending!(id), do: Repo.get!(Ending, id)

  @doc "Fetch an ending **within** `scenario`, or nil. Use for request-scoped reads."
  def get_ending(%Scenario{} = scenario, id) do
    if uuid = valid_uuid(id), do: Repo.get_by(Ending, id: uuid, scenario_id: scenario.id)
  end

  def create_ending(%Scenario{} = scenario, attrs) do
    scenario
    |> Ecto.build_assoc(:endings)
    |> Ending.changeset(attrs, value_keys: value_keys(scenario.id))
    |> Repo.insert()
  end

  def update_ending(%Ending{} = ending, attrs) do
    ending
    |> Ending.changeset(attrs, value_keys: value_keys(ending.scenario_id))
    |> Repo.update()
  end

  def delete_ending(%Ending{} = ending), do: Repo.delete(ending)

  def change_ending(%Ending{} = ending, attrs \\ %{}), do: Ending.changeset(ending, attrs)

  # ── Internal ──────────────────────────────────────────────────────────────

  # Cast a client-supplied id to a canonical UUID, or nil when malformed — so
  # scenario-scoped getters return "not found" instead of raising on garbage.
  defp valid_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end
end
