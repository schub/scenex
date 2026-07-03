defmodule Scenex.Authoring.DecisionOption do
  @moduledoc """
  One option on a timeline element. What it means depends on the element's kind:

    * **event** — one choice for a specific group (`group_id` required); its
      effects hit that group's own values (`OptionEffect.group_id` nil).
    * **election** — one ballot option for the whole room (`group_id` nil);
      its effects form an outcome matrix (explicit target groups).
    * **sidequest** — one outcome bundle (`outcome`: success or failure,
      `group_id` nil); effects form an outcome matrix.

  `condition` is an optional gate (see `Scenex.Engine.Condition`): unmet
  options are shown greyed-out, never hidden. Gates are allowed on event
  options (`self` + `global`) and election options (`global` only) — not on
  sidequest outcomes (nobody chooses them; the GM adjudicates).

  `is_default` marks the option auto-applied when a deadline lapses.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{TimelineElement, Group, Label, OptionEffect}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @outcomes [:success, :failure]
  def outcomes, do: @outcomes

  schema "decision_options" do
    field :handle, :string
    field :text, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :condition, :string
    field :outcome, Ecto.Enum, values: @outcomes
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :timeline_element, TimelineElement
    belongs_to :group, Group
    has_many :effects, OptionEffect
    many_to_many :labels, Label, join_through: "decision_option_labels", on_replace: :delete

    timestamps()
  end

  @doc """
  Options:

    * `:kind` — the timeline element's kind (default `:event`); drives which
      fields are required or forbidden.
    * `:value_keys` — known value keys for condition validation (optional).
  """
  def changeset(decision_option, attrs, opts \\ []) do
    kind = Keyword.get(opts, :kind, :event)

    decision_option
    |> cast(attrs, [
      :timeline_element_id,
      :group_id,
      :handle,
      :text,
      :director_notes,
      :condition,
      :outcome,
      :is_default,
      :position
    ])
    |> validate_required([:timeline_element_id, :handle])
    |> validate_localized_required(:text)
    |> validate_by_kind(kind, Keyword.get(opts, :value_keys))
    |> assoc_constraint(:timeline_element)
    |> unique_constraint(:handle,
      name: :decision_options_timeline_element_id_handle_index,
      message: "is already used in this timeline element"
    )
  end

  defp validate_by_kind(changeset, :event, value_keys) do
    changeset
    |> validate_required([:group_id])
    |> forbid_field(:outcome, "only sidequest options have an outcome")
    |> validate_condition(:condition, allow_self: true, keys: value_keys)
    |> assoc_constraint(:group)
  end

  defp validate_by_kind(changeset, :election, value_keys) do
    changeset
    |> forbid_field(:group_id, "election options belong to the whole room, not a group")
    |> forbid_field(:outcome, "only sidequest options have an outcome")
    |> validate_condition(:condition, allow_self: false, keys: value_keys)
  end

  defp validate_by_kind(changeset, :sidequest, _value_keys) do
    changeset
    |> validate_required([:outcome])
    |> forbid_field(:group_id, "the group is bound at adjudication time, not authored")
    |> forbid_field(:condition, "sidequest outcomes are adjudicated, not gated")
  end

  defp forbid_field(changeset, field, message) do
    if get_field(changeset, field) == nil,
      do: changeset,
      else: add_error(changeset, field, message)
  end
end
