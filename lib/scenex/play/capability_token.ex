defmodule Scenex.Play.CapabilityToken do
  @moduledoc """
  An ephemeral capability for one session, handed out as a QR code — no
  account, no login. The scope is baked into the token itself:

    * `:group` — write access for **exactly one group** in exactly one
      session (the group's table enters its own decisions).
    * `:display` — read-only access for the projected board.

  Tokens die with their session (rows cascade) and may carry an optional
  `expires_at`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Authoring.Group
  alias Scenex.Play.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @kinds [:group, :display]
  def kinds, do: @kinds

  schema "capability_tokens" do
    field :kind, Ecto.Enum, values: @kinds
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :group, Group

    timestamps()
  end

  def changeset(capability_token, attrs) do
    capability_token
    |> cast(attrs, [:session_id, :kind, :group_id, :token, :expires_at])
    |> validate_required([:session_id, :kind, :token])
    |> validate_group_for_kind()
    |> assoc_constraint(:session)
    |> unique_constraint(:token)
  end

  defp validate_group_for_kind(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :group_id)} do
      {:group, nil} ->
        add_error(changeset, :group_id, "group tokens need a group")

      {:display, id} when not is_nil(id) ->
        add_error(changeset, :group_id, "display tokens have no group")

      _ ->
        changeset
    end
  end

  def generate, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
end
