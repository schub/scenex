defmodule Scenex.Authoring.Scenario do
  @moduledoc "A scenario definition — the editable, reusable content of one scenario."
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{TimelineElement, Group, ScenarioMembership, Label, ValueDimension}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @visibilities [:draft, :invite_only, :published]
  def visibilities, do: @visibilities

  schema "scenarios" do
    field :handle, :string
    field :name, :map, default: %{}
    field :tagline, :map, default: %{}
    field :description, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :source_locale, :string, default: "en"
    field :visibility, Ecto.Enum, values: @visibilities, default: :draft
    field :change_highlight_seconds, :integer, default: 30

    has_many :memberships, ScenarioMembership
    has_many :endings, Scenex.Authoring.Ending
    has_many :value_dimensions, ValueDimension
    has_many :groups, Group
    has_many :timeline_elements, TimelineElement
    has_many :labels, Label

    timestamps()
  end

  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [
      :handle,
      :name,
      :tagline,
      :description,
      :director_notes,
      :source_locale,
      :visibility,
      :change_highlight_seconds
    ])
    |> validate_required([:handle, :source_locale, :change_highlight_seconds])
    |> validate_number(:change_highlight_seconds, greater_than_or_equal_to: 0)
    |> validate_localized_required(:name)
    |> validate_format(:source_locale, ~r/^[a-z]{2}(-[A-Za-z]{2,})?$/,
      message: "must be a locale code like \"en\" or \"pt-BR\""
    )
  end
end
