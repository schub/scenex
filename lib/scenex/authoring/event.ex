defmodule Scenex.Authoring.Event do
  @moduledoc """
  An ordered beat on the game timeline. Fired by the GM during a session
  (`trigger: :manual` in v1); a `deadline_seconds` measured against the session's
  game clock drives the default consequence. `kind` (event/election/sidequest) is
  an inert label in v1 — all kinds behave identically.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{DecisionOption, Game}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @kinds [:event, :election, :sidequest]
  @triggers [:manual]
  def kinds, do: @kinds
  def triggers, do: @triggers

  schema "events" do
    field :handle, :string
    field :title, :map, default: %{}
    field :narrative, :map, default: %{}
    field :position, :integer, default: 0
    field :kind, Ecto.Enum, values: @kinds, default: :event
    field :trigger, Ecto.Enum, values: @triggers, default: :manual
    field :deadline_seconds, :integer

    belongs_to :game, Game
    has_many :decision_options, DecisionOption

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :game_id,
      :handle,
      :title,
      :narrative,
      :position,
      :kind,
      :trigger,
      :deadline_seconds
    ])
    |> validate_required([:game_id, :handle, :kind, :trigger])
    |> validate_localized_required(:title)
    |> validate_number(:deadline_seconds, greater_than: 0)
    |> assoc_constraint(:game)
  end
end
