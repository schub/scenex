defmodule Scenex.Authoring.GameMembership do
  @moduledoc """
  Authoring-side membership: which user has which role on a game *definition*.

  These roles govern the CMS only (`owner` / `author` can edit, `viewer` can
  read). They are unrelated to *playing* a published game, which happens through
  sessions (Layer 3) and capability tokens.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Accounts.User
  alias Scenex.Authoring.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @roles [:owner, :author, :viewer]
  def roles, do: @roles

  schema "game_memberships" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :game, Game
    belongs_to :user, User

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:game_id, :user_id, :role])
    |> validate_required([:game_id, :user_id, :role])
    |> assoc_constraint(:game)
    |> assoc_constraint(:user)
    |> unique_constraint([:game_id, :user_id])
  end
end
