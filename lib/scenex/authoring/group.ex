defmodule Scenex.Authoring.Group do
  @moduledoc "A player faction. Carries per-group values via GroupInitialValue."
  use Ecto.Schema

  import Ecto.Changeset
  import Scenex.Authoring.Validators

  alias Scenex.Authoring.{Scenario, GroupInitialValue}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "groups" do
    field :key, :string
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :position, :integer, default: 0
    # Soft delete (see Authoring.delete_group/1) — not castable via changeset.
    field :archived_at, :utc_datetime

    belongs_to :scenario, Scenario
    has_many :initial_values, GroupInitialValue

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:scenario_id, :key, :name, :description, :director_notes, :position])
    |> validate_required([:scenario_id, :key])
    |> validate_localized_required(:name)
    |> assoc_constraint(:scenario)
    |> unique_constraint(:key,
      name: :groups_scenario_id_key_index,
      message: "is already used in this scenario"
    )
  end
end
