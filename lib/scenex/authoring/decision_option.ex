defmodule Scenex.Authoring.DecisionOption do
  @moduledoc """
  One option a specific group may choose at an event. The group's option set is
  simply the options with that `group_id`. Choosing an option applies its
  `OptionEffect`s to that same group's own values. `is_default` is the option
  auto-applied if the deadline lapses.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Event, Group, Label, OptionEffect}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "decision_options" do
    field :handle, :string
    field :text, :map, default: %{}
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :event, Event
    belongs_to :group, Group
    has_many :effects, OptionEffect
    many_to_many :labels, Label, join_through: "decision_option_labels", on_replace: :delete

    timestamps()
  end

  def changeset(decision_option, attrs) do
    decision_option
    |> cast(attrs, [:event_id, :group_id, :handle, :text, :is_default, :position])
    |> validate_required([:event_id, :group_id, :handle])
    |> validate_localized_required(:text)
    |> assoc_constraint(:event)
    |> assoc_constraint(:group)
  end
end
