defmodule Scenex.Repo.Migrations.AddLabelToValueDimensionSteps do
  use Ecto.Migration

  # An optional localized name per readout step (e.g. "Thriving"), shown
  # alongside the emoji in the GM tally grid. Existing steps default to none.
  def change do
    alter table(:value_dimension_steps) do
      add :label, :map, null: false, default: %{}
    end
  end
end
