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

    # The scoreboard's single derived "Democracy Score": a formula (same
    # language as a value's aggregation) evaluated over the globals of every
    # `:per_group` value dimension. Nil formula/min/max means unconfigured —
    # the scoreboard section simply has nothing to show.
    field :democracy_formula, :string
    field :democracy_min, :float
    field :democracy_max, :float

    # Optional: a narrower range used only for the gauge's tick position, so
    # small real-world swings (a score that in practice never nears the true
    # ends) still read as real movement. The band labels and the dry run's
    # precise lookup keep using the real min/max above — this only changes
    # where the dot sits. nil (either bound) means "use the real range."
    field :democracy_viz_min, :float
    field :democracy_viz_max, :float

    has_many :memberships, ScenarioMembership
    has_many :endings, Scenex.Authoring.Ending
    has_many :value_dimensions, ValueDimension
    has_many :groups, Group
    has_many :timeline_elements, TimelineElement
    has_many :labels, Label
    has_many :pages, Scenex.Authoring.Page
    has_many :democracy_bands, Scenex.Authoring.DemocracyBand

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
      :democracy_formula,
      :democracy_min,
      :democracy_max,
      :democracy_viz_min,
      :democracy_viz_max
    ])
    |> validate_required([:handle, :source_locale, :change_highlight_seconds])
    |> validate_number(:change_highlight_seconds, greater_than_or_equal_to: 0)
    |> validate_localized_required(:name)
    |> validate_format(:source_locale, ~r/^[a-z]{2}(-[A-Za-z]{2,})?$/,
      message: "must be a locale code like \"en\" or \"pt-BR\""
    )
    |> maybe_validate_formula(:democracy_formula)
    |> validate_min_max(:democracy_min, :democracy_max)
    |> validate_min_max(:democracy_viz_min, :democracy_viz_max)
    |> validate_viz_range_within_real_range()
  end

  defp maybe_validate_formula(changeset, field) do
    if get_field(changeset, field) in [nil, ""],
      do: changeset,
      else: validate_formula(changeset, field)
  end

  # The visualization range only makes sense as a subset of the real one —
  # anything else can't be "exaggerate the middle of the real range."
  defp validate_viz_range_within_real_range(changeset) do
    real_min = get_field(changeset, :democracy_min)
    real_max = get_field(changeset, :democracy_max)
    viz_min = get_field(changeset, :democracy_viz_min)
    viz_max = get_field(changeset, :democracy_viz_max)

    cond do
      is_nil(viz_min) or is_nil(viz_max) ->
        changeset

      is_nil(real_min) or is_nil(real_max) ->
        add_error(changeset, :democracy_viz_min, "needs a democracy score min/max set first")

      viz_min < real_min or viz_max > real_max ->
        add_error(
          changeset,
          :democracy_viz_min,
          "must be within the democracy score's own min/max"
        )

      true ->
        changeset
    end
  end
end
