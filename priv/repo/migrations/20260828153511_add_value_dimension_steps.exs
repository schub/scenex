defmodule Scenex.Repo.Migrations.AddValueDimensionSteps do
  use Ecto.Migration

  # Per-participant values used to render on one hardcoded 1..4 smiley scale.
  # Steps make that scale first-class and author-defined: an ordered list of
  # emoji (worst -> best, position ascending), one row per step.
  #
  # Backfill every existing per-participant value with the legacy four-smiley
  # scale so running scenarios render exactly as before.

  @legacy_steps [{1, "🙁"}, {2, "😐"}, {3, "🙂"}, {4, "😀"}]

  def up do
    create table(:value_dimension_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :value_dimension_id,
          references(:value_dimensions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :position, :integer, null: false, default: 0
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:value_dimension_steps, [:value_dimension_id])

    flush()

    %{rows: rows} =
      repo().query!("SELECT id FROM value_dimensions WHERE input_scope = 'per_participant'", [])

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    for [vd_id] <- rows, {position, emoji} <- @legacy_steps do
      repo().query!(
        """
        INSERT INTO value_dimension_steps
          (id, value_dimension_id, position, emoji, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $5)
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), vd_id, position, emoji, now]
      )
    end
  end

  def down do
    drop table(:value_dimension_steps)
  end
end
