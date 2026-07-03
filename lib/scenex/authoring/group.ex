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
    field :handle, :string
    field :name, :map, default: %{}
    field :description, :map, default: %{}
    field :director_notes, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :scenario, Scenario
    has_many :initial_values, GroupInitialValue

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:scenario_id, :handle, :name, :description, :director_notes, :position])
    |> validate_required([:scenario_id, :handle])
    |> validate_localized_required(:name)
    |> assoc_constraint(:scenario)
    |> unique_constraint(:handle,
      name: :groups_scenario_id_handle_index,
      message: "is already used in this scenario"
    )
  end
end
