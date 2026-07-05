defmodule Scenex.Authoring.ScenarioInvitation do
  @moduledoc """
  A pending invitation to join a scenario's authoring team by email.

  Registration is closed to the public: invitations are the only way new
  accounts get created. The invitee receives a link containing a random
  token; only its hash is stored (same scheme as `Scenex.Accounts.UserToken`),
  so database access alone cannot forge an acceptance link. Accepting creates
  the account (with a password) if needed and adds a `ScenarioMembership`
  with the invited role. Invitations are deleted on acceptance or revocation.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Scenex.Accounts.User
  alias Scenex.Authoring.{Scenario, ScenarioInvitation}

  @hash_algorithm :sha256
  @rand_size 32
  @validity_in_days 7

  # Owners are created by owning, not by invitation.
  @invitable_roles [:author, :viewer]
  def invitable_roles, do: @invitable_roles

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "scenario_invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: @invitable_roles
    field :token, :binary, redact: true

    belongs_to :scenario, Scenario
    belongs_to :invited_by, User

    timestamps()
  end

  @doc """
  Builds `{encoded_token, changeset}` for a new invitation.

  The encoded token goes into the emailed URL; only its hash is persisted.
  """
  def build(%Scenario{} = scenario, %User{} = inviter, email, role) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    changeset =
      %ScenarioInvitation{}
      |> cast(%{email: email, role: role}, [:email, :role])
      |> validate_required([:email, :role])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)
      |> put_change(:token, hashed_token)
      |> put_assoc(:scenario, scenario)
      |> put_assoc(:invited_by, inviter)
      |> unique_constraint([:scenario_id, :email],
        message: "has already been invited to this scenario"
      )

    {Base.url_encode64(token, padding: false), changeset}
  end

  @doc """
  Returns a query resolving an encoded token to a non-expired invitation
  (with scenario preloaded), or `:error` for malformed tokens.
  """
  def verify_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from i in ScenarioInvitation,
            where: i.token == ^hashed_token,
            where: i.inserted_at > ago(@validity_in_days, "day"),
            preload: [:scenario]

        {:ok, query}

      :error ->
        :error
    end
  end
end
