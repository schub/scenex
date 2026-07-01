defmodule Scenex.Authoring do
  @moduledoc """
  The Authoring context (Layer 2) — creating and maintaining game *definitions*.

  Plain CRUD over the definition graph (games, values, groups, events, options,
  effects, labels), plus authorization. Authorization lives here, not in
  LiveViews: `get_game_for_user/2`, `can_edit?/2`, `is_owner?/2`, `get_user_role/2`.

  `owner`/`author` may edit; `viewer` (and anyone, for a `:published` game) may
  read. These roles are unrelated to *playing* a game (Layer 3).
  """

  import Ecto.Query, warn: false

  alias Scenex.Accounts.User
  alias Scenex.Engine.ValueSpec
  alias Scenex.Repo

  alias Scenex.Authoring.{
    DecisionOption,
    Event,
    Game,
    GameMembership,
    Group,
    GroupInitialValue,
    Label,
    OptionEffect,
    ValueDefinition
  }

  # ── Games ───────────────────────────────────────────────────────────────

  @doc "Games the user may see: any they're a member of, plus published ones."
  def list_games_for_user(%User{} = user) do
    Repo.all(
      from g in Game,
        left_join: m in GameMembership,
        on: m.game_id == g.id and m.user_id == ^user.id,
        where: not is_nil(m.id) or g.visibility == :published,
        distinct: true,
        order_by: [desc: g.updated_at]
    )
  end

  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Fetch a game the user may access, returning `{game, role}` or `nil`.
  Route request reads through this rather than `get_game!/1`.
  """
  def get_game_for_user(id, user) do
    case Repo.get(Game, id) do
      nil ->
        nil

      game ->
        case get_user_role(game, user) do
          nil -> nil
          role -> {game, role}
        end
    end
  end

  @doc "Create a game and make its creator the owner, atomically."
  def create_game(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:game, Game.changeset(%Game{}, attrs))
    |> Ecto.Multi.insert(:membership, fn %{game: game} ->
      GameMembership.changeset(%GameMembership{}, %{
        game_id: game.id,
        user_id: user.id,
        role: :owner
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{game: game}} -> {:ok, game}
      {:error, :game, changeset, _} -> {:error, changeset}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def update_game(%Game{} = game, attrs),
    do: game |> Game.changeset(attrs) |> Repo.update()

  def delete_game(%Game{} = game), do: Repo.delete(game)

  def change_game(%Game{} = game, attrs \\ %{}), do: Game.changeset(game, attrs)

  # ── Authorization ───────────────────────────────────────────────────────

  @doc "The user's role on a game: `:owner | :author | :viewer | nil`."
  def get_user_role(game, user)

  def get_user_role(%Game{} = game, %User{} = user) do
    membership_role =
      Repo.one(
        from m in GameMembership,
          where: m.game_id == ^game.id and m.user_id == ^user.id,
          select: m.role
      )

    membership_role || public_role(game)
  end

  def get_user_role(%Game{} = game, nil), do: public_role(game)

  defp public_role(%Game{visibility: :published}), do: :viewer
  defp public_role(_game), do: nil

  def can_edit?(game, user), do: get_user_role(game, user) in [:owner, :author]

  def is_owner?(game, user), do: get_user_role(game, user) == :owner

  # ── Membership ──────────────────────────────────────────────────────────

  def list_members(%Game{} = game) do
    Repo.all(from m in GameMembership, where: m.game_id == ^game.id, preload: [:user])
  end

  def add_member(%Game{} = game, %User{} = user, role) do
    %GameMembership{}
    |> GameMembership.changeset(%{game_id: game.id, user_id: user.id, role: role})
    |> Repo.insert()
  end

  def remove_member(%GameMembership{} = membership), do: Repo.delete(membership)

  # ── Value definitions ───────────────────────────────────────────────────

  def list_value_definitions(%Game{} = game) do
    Repo.all(from v in ValueDefinition, where: v.game_id == ^game.id, order_by: v.position)
  end

  def get_value_definition!(id), do: Repo.get!(ValueDefinition, id)

  def create_value_definition(%Game{} = game, attrs) do
    game
    |> Ecto.build_assoc(:value_definitions)
    |> ValueDefinition.changeset(attrs)
    |> Repo.insert()
  end

  def update_value_definition(%ValueDefinition{} = vd, attrs),
    do: vd |> ValueDefinition.changeset(attrs) |> Repo.update()

  def delete_value_definition(%ValueDefinition{} = vd), do: Repo.delete(vd)

  def change_value_definition(%ValueDefinition{} = vd, attrs \\ %{}),
    do: ValueDefinition.changeset(vd, attrs)

  @doc "Project a value definition into the pure engine's `ValueSpec` (id as key)."
  def to_value_spec(%ValueDefinition{} = vd) do
    %ValueSpec{
      key: vd.id,
      aggregation: vd.aggregation,
      min: vd.min,
      max: vd.max,
      input_scope: vd.input_scope
    }
  end

  # ── Groups ──────────────────────────────────────────────────────────────

  def list_groups(%Game{} = game) do
    Repo.all(from g in Group, where: g.game_id == ^game.id, order_by: g.position)
  end

  def get_group!(id), do: Repo.get!(Group, id)

  def create_group(%Game{} = game, attrs) do
    game
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
  def set_group_initial_value(%Group{} = group, %ValueDefinition{} = vd, initial) do
    %GroupInitialValue{}
    |> GroupInitialValue.changeset(%{
      group_id: group.id,
      value_definition_id: vd.id,
      initial: initial
    })
    |> Repo.insert(
      on_conflict: {:replace, [:initial, :updated_at]},
      conflict_target: [:group_id, :value_definition_id]
    )
  end

  def list_group_initial_values(%Group{} = group) do
    Repo.all(from giv in GroupInitialValue, where: giv.group_id == ^group.id)
  end

  # ── Events ──────────────────────────────────────────────────────────────

  def list_events(%Game{} = game) do
    Repo.all(from e in Event, where: e.game_id == ^game.id, order_by: e.position)
  end

  def get_event!(id), do: Repo.get!(Event, id)

  def create_event(%Game{} = game, attrs) do
    game
    |> Ecto.build_assoc(:events)
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def update_event(%Event{} = event, attrs),
    do: event |> Event.changeset(attrs) |> Repo.update()

  def delete_event(%Event{} = event), do: Repo.delete(event)

  def change_event(%Event{} = event, attrs \\ %{}), do: Event.changeset(event, attrs)

  # ── Decision options ────────────────────────────────────────────────────

  def list_decision_options(%Event{} = event) do
    Repo.all(
      from o in DecisionOption,
        where: o.event_id == ^event.id,
        order_by: [o.group_id, o.position]
    )
  end

  def list_decision_options_for_group(%Event{} = event, %Group{} = group) do
    Repo.all(
      from o in DecisionOption,
        where: o.event_id == ^event.id and o.group_id == ^group.id,
        order_by: o.position
    )
  end

  def get_decision_option!(id), do: Repo.get!(DecisionOption, id)

  def create_decision_option(%Event{} = event, %Group{} = group, attrs) do
    event
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
  def set_option_effect(%DecisionOption{} = option, %ValueDefinition{} = vd, delta) do
    %OptionEffect{}
    |> OptionEffect.changeset(%{
      decision_option_id: option.id,
      value_definition_id: vd.id,
      delta: delta
    })
    |> Repo.insert(
      on_conflict: {:replace, [:delta, :updated_at]},
      conflict_target: [:decision_option_id, :value_definition_id]
    )
  end

  def list_option_effects(%DecisionOption{} = option) do
    Repo.all(from oe in OptionEffect, where: oe.decision_option_id == ^option.id)
  end

  # ── Labels ──────────────────────────────────────────────────────────────

  def list_labels(%Game{} = game) do
    Repo.all(from l in Label, where: l.game_id == ^game.id, order_by: l.position)
  end

  def get_label!(id), do: Repo.get!(Label, id)

  def create_label(%Game{} = game, attrs) do
    game
    |> Ecto.build_assoc(:labels)
    |> Label.changeset(attrs)
    |> Repo.insert()
  end

  def update_label(%Label{} = label, attrs),
    do: label |> Label.changeset(attrs) |> Repo.update()

  def delete_label(%Label{} = label), do: Repo.delete(label)

  def change_label(%Label{} = label, attrs \\ %{}), do: Label.changeset(label, attrs)
end
