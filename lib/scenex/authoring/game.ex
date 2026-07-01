defmodule Scenex.Authoring.Game do
  @moduledoc "A game definition — the editable, reusable content of one game."
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Event, Group, GameMembership, Label, ValueDefinition}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @visibilities [:draft, :invite_only, :published]
  def visibilities, do: @visibilities

  schema "games" do
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :source_locale, :string, default: "en"
    field :visibility, Ecto.Enum, values: @visibilities, default: :draft

    has_many :memberships, GameMembership
    has_many :value_definitions, ValueDefinition
    has_many :groups, Group
    has_many :events, Event
    has_many :labels, Label

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:name, :description, :source_locale, :visibility])
    |> validate_required([:source_locale])
    |> validate_localized_required(:name)
    |> validate_format(:source_locale, ~r/^[a-z]{2}(-[A-Za-z]{2,})?$/,
      message: "must be a locale code like \"en\" or \"pt-BR\""
    )
  end
end
