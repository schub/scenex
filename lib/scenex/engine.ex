defmodule Scenex.Engine do
  @moduledoc """
  Layer 1 — the pure game engine.

  The engine is the "rules of physics" shared by every game: how per-group values
  aggregate into globals, and how decision effects shift values. It is **pure** —
  no Ecto, no processes, no I/O — which makes it exhaustively unit-testable and
  lets the exact same code drive both simulate mode (Layer 2) and live sessions
  (Layer 3).

  Building blocks:

    * `Scenex.Engine.Formula` — aggregation formula parser/evaluator
    * `Scenex.Engine.ValueSpec` — engine-level value specification
    * `Scenex.Engine.Sim` — the pure numeric state and its operations
  """

  alias Scenex.Engine.Formula

  @doc "Validate an aggregation formula. See `Scenex.Engine.Formula.validate/1`."
  defdelegate validate_formula(formula), to: Formula, as: :validate

  @doc "Evaluate an aggregation formula against group values."
  defdelegate evaluate_formula(formula, values), to: Formula, as: :evaluate
end
