defmodule Scenex.Authoring.TimelineElement do
  @moduledoc """
  An ordered beat on the scenario timeline. Fired by the GM during a session
  (`trigger: :manual` in v1); a `deadline_seconds` measured against the session's
  game clock drives the default consequence. `kind` (event/election/sidequest)
  determines the mechanics; v1 still treats kinds identically (changes in
  Phase 2.5).
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{DecisionOption, Scenario}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @kinds [:event, :election, :sidequest]
  @triggers [:manual]
  def kinds, do: @kinds
  def triggers, do: @triggers

  schema "timeline_elements" do
    field :handle, :string
    field :title, :map, default: %{}
    field :narrative, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :position, :integer, default: 0
    field :kind, Ecto.Enum, values: @kinds, default: :event
    field :trigger, Ecto.Enum, values: @triggers, default: :manual
    field :deadline_seconds, :integer

    belongs_to :scenario, Scenario
    has_many :decision_options, DecisionOption

    timestamps()
  end

  def changeset(timeline_element, attrs) do
    timeline_element
    |> cast(attrs, [
      :scenario_id,
      :handle,
      :title,
      :narrative,
      :director_notes,
      :position,
      :kind,
      :trigger,
      :deadline_seconds
    ])
    |> validate_required([:scenario_id, :handle, :kind, :trigger])
    |> validate_localized_required(:title)
    |> validate_number(:deadline_seconds, greater_than: 0)
    |> assoc_constraint(:scenario)
    |> unique_constraint(:handle,
      name: :timeline_elements_scenario_id_handle_index,
      message: "is already used in this scenario"
    )
  end
end
