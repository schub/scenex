defmodule Scenex.Play.Session do
  @moduledoc """
  One live run of a scenario, at one venue, on one day (Layer 3).

  The row holds *operational* state: status, the pausable game clock
  (`game_time_ms` accumulated + `clock_started_at` while running), and the
  ending the GM finally selected. The *game history* lives in the append-only
  `SessionEvent` log; the current board is derived by folding it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Accounts.User
  alias Scenex.Authoring.{Ending, Scenario}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @statuses [:draft, :live, :paused, :ended]
  def statuses, do: @statuses

  schema "sessions" do
    field :label, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :game_time_ms, :integer, default: 0
    field :clock_started_at, :utc_datetime_usec

    belongs_to :scenario, Scenario
    belongs_to :ending, Ending
    belongs_to :created_by, User

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:scenario_id, :label, :created_by_id])
    |> validate_required([:scenario_id, :label])
    |> assoc_constraint(:scenario)
  end
end
