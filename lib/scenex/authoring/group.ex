defmodule Scenex.Authoring.Group do
  @moduledoc "A player faction. Carries per-group values via GroupInitialValue."
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Game, GroupInitialValue}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "groups" do
    field :handle, :string
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :game, Game
    has_many :initial_values, GroupInitialValue

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:game_id, :handle, :name, :description, :position])
    |> validate_required([:game_id, :handle])
    |> validate_localized_required(:name)
    |> assoc_constraint(:game)
  end
end
