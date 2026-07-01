defmodule Scenex.Engine.ValueSpec do
  @moduledoc """
  The numeric specification of a value, as the pure engine needs it.

  This is the engine-level projection of a `ValueDefinition` (Layer 2), stripped
  of localized names and persistence concerns:

    * `:key` — a stable identifier (atom or string)
    * `:aggregation` — the formula string used to derive the global value from
      per-group values (see `Scenex.Engine.Formula`)
    * `:min` / `:max` — optional clamping bounds for per-group values
    * `:input_scope` — `:per_group` (factions enter numbers) or
      `:per_participant` (individuals vote; aggregated separately)
  """

  @enforce_keys [:key, :aggregation]
  defstruct [:key, :aggregation, :min, :max, input_scope: :per_group]

  @type key :: atom() | String.t()
  @type t :: %__MODULE__{
          key: key(),
          aggregation: String.t(),
          min: number() | nil,
          max: number() | nil,
          input_scope: :per_group | :per_participant
        }
end
