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
  alias Scenex.Authoring.{Ending, Group, Scenario}
  alias Scenex.Play.SessionGroup

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @statuses [:draft, :live, :paused, :ended]
  def statuses, do: @statuses

  schema "sessions" do
    field :label, :string
    field :locale, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :game_time_ms, :integer, default: 0
    field :clock_started_at, :utc_datetime_usec

    belongs_to :scenario, Scenario
    belongs_to :ending, Ending
    belongs_to :created_by, User

    # Selected at creation, immutable afterwards; empty means "all groups".
    many_to_many :groups, Group, join_through: SessionGroup

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:scenario_id, :label, :locale, :created_by_id])
    |> validate_required([:scenario_id, :label])
    |> validate_format(:locale, ~r/^[a-z]{2}(-[A-Za-z]{2,})?$/,
      message: "must be a locale code like \"en\" or \"pt-BR\""
    )
    |> assoc_constraint(:scenario)
  end
end
