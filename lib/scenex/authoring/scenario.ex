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

    # The scoreboard's single derived "Overall Index": the headline metric the
    # scenario's values roll up into, which the author labels for their setting
    # (`name`/`description`, e.g. "Democracy", "Ship Integrity"). Its
    # `overall_index_formula` combines value globals by key (see
    # `Scenex.Engine.Index`). Nil formula/min/max means unconfigured — the
    # scoreboard section simply has nothing to show.
    field :overall_index_name, :map, default: %{}
    field :overall_index_description, :map, default: %{}
    field :overall_index_formula, :string
    field :overall_index_min, :float
    field :overall_index_max, :float

    # Optional: a narrower range used only for the gauge's tick position, so
    # small real-world swings (a score that in practice never nears the true
    # ends) still read as real movement. The band labels and the dry run's
    # precise lookup keep using the real min/max above — this only changes
    # where the dot sits. nil (either bound) means "use the real range."
    field :overall_index_viz_min, :float
    field :overall_index_viz_max, :float

    has_many :memberships, ScenarioMembership
    has_many :endings, Scenex.Authoring.Ending
    has_many :value_dimensions, ValueDimension
    has_many :groups, Group
    has_many :timeline_elements, TimelineElement
    has_many :labels, Label
    has_many :pages, Scenex.Authoring.Page
    has_many :overall_index_bands, Scenex.Authoring.OverallIndexBand

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
      :change_highlight_seconds,
      :overall_index_name,
      :overall_index_description,
      :overall_index_formula,
      :overall_index_min,
      :overall_index_max,
      :overall_index_viz_min,
      :overall_index_viz_max
    ])
    |> validate_required([:handle, :source_locale, :change_highlight_seconds])
    |> validate_number(:change_highlight_seconds, greater_than_or_equal_to: 0)
    |> validate_localized_required(:name)
    |> validate_format(:source_locale, ~r/^[a-z]{2}(-[A-Za-z]{2,})?$/,
      message: "must be a locale code like \"en\" or \"pt-BR\""
    )
    |> maybe_validate_index_formula(:overall_index_formula)
    |> validate_min_max(:overall_index_min, :overall_index_max)
    |> validate_min_max(:overall_index_viz_min, :overall_index_viz_max)
    |> validate_viz_range_within_real_range()
  end

  defp maybe_validate_index_formula(changeset, field) do
    if get_field(changeset, field) in [nil, ""],
      do: changeset,
      else: validate_index_formula(changeset, field)
  end

  # The visualization range only makes sense as a subset of the real one —
  # anything else can't be "exaggerate the middle of the real range."
  defp validate_viz_range_within_real_range(changeset) do
    real_min = get_field(changeset, :overall_index_min)
    real_max = get_field(changeset, :overall_index_max)
    viz_min = get_field(changeset, :overall_index_viz_min)
    viz_max = get_field(changeset, :overall_index_viz_max)

    cond do
      is_nil(viz_min) or is_nil(viz_max) ->
        changeset

      is_nil(real_min) or is_nil(real_max) ->
        add_error(changeset, :overall_index_viz_min, "needs an overall index min/max set first")

      viz_min < real_min or viz_max > real_max ->
        add_error(
          changeset,
          :overall_index_viz_min,
          "must be within the overall index's own min/max"
        )

      true ->
        changeset
    end
  end
end
