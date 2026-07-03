defmodule Scenex.Authoring.Ending do
  @moduledoc """
  An authored final scene. Pure content — an ending applies no effects and
  computes nothing; the game is over when one is chosen.

  The optional `condition` (over **global** values only) is evaluated against
  the final state to *recommend* matching endings; the GM picks and may
  override. `priority` orders recommendations (higher first).
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.Scenario

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "endings" do
    field :handle, :string
    field :title, :map, default: %{}
    field :narrative, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :condition, :string
    field :priority, :integer, default: 0

    belongs_to :scenario, Scenario

    timestamps()
  end

  def changeset(ending, attrs, opts \\ []) do
    ending
    |> cast(attrs, [
      :scenario_id,
      :handle,
      :title,
      :narrative,
      :director_notes,
      :condition,
      :priority
    ])
    |> validate_required([:scenario_id, :handle])
    |> validate_localized_required(:title)
    |> validate_condition(:condition,
      allow_self: false,
      keys: Keyword.get(opts, :value_keys)
    )
    |> assoc_constraint(:scenario)
    |> unique_constraint(:handle,
      name: :endings_scenario_id_handle_index,
      message: "is already used in this scenario"
    )
  end
end
