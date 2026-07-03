defmodule Scenex.Authoring.ScenarioMembership do
  @moduledoc """
  Authoring-side membership: which user has which role on a scenario *definition*.

  These roles govern the CMS only (`owner` / `author` can edit, `viewer` can
  read). They are unrelated to *playing* a published scenario, which happens through
  sessions (Layer 3) and capability tokens.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Accounts.User
  alias Scenex.Authoring.Scenario

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @roles [:owner, :author, :viewer]
  def roles, do: @roles

  schema "scenario_memberships" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :scenario, Scenario
    belongs_to :user, User

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:scenario_id, :user_id, :role])
    |> validate_required([:scenario_id, :user_id, :role])
    |> assoc_constraint(:scenario)
    |> assoc_constraint(:user)
    |> unique_constraint([:scenario_id, :user_id])
  end
end
