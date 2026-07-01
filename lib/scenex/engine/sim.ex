defmodule Scenex.Engine.Sim do
  @moduledoc """
  The pure numeric state of a game in play, and the operations over it.

  A `Sim` holds the current per-group value for every `per_group` value, plus the
  specs needed to clamp effects and derive globals. It is **pure**: no Ecto, no
  processes. The same code powers Phase 2 simulate mode and the Phase 3 live
  session `GenServer` (which holds a `Sim` and folds session events into it).

  Global values are always *derived* from the per-group values via each value's
  aggregation formula — never stored, never entered directly.

  ## Example

      iex> alias Scenex.Engine.{Sim, ValueSpec}
      iex> specs = [%ValueSpec{key: :stability, aggregation: "avg", min: 0, max: 100}]
      iex> sim = Sim.new(specs, [:gov, :media], %{stability: %{gov: 60, media: 40}})
      iex> Sim.globals(sim)
      %{stability: 50.0}
      iex> sim |> Sim.apply_effect(:stability, :gov, -100) |> Sim.get(:stability, :gov)
      0
  """

  alias Scenex.Engine.{Formula, ValueSpec}

  @type key :: ValueSpec.key()
  @type group_id :: term()
  @type effect :: {key(), group_id(), number()}

  @type t :: %__MODULE__{
          specs: %{optional(key()) => ValueSpec.t()},
          groups: [group_id()],
          group_values: %{optional(key()) => %{optional(group_id()) => number()}}
        }

  defstruct specs: %{}, groups: [], group_values: %{}

  @doc """
  Build a simulation from value specs, the list of groups, and optional initial
  per-group values (`%{value_key => %{group_id => number}}`).

  Only `:per_group` values get seeded. Missing initial values default to the
  value's `:min` (or `0`). All seeds are clamped to the value's bounds.
  """
  @spec new([ValueSpec.t()], [group_id()], map()) :: t()
  def new(specs, groups, initial \\ %{}) when is_list(specs) and is_list(groups) do
    specs_map = Map.new(specs, fn %ValueSpec{key: key} = spec -> {key, spec} end)

    group_values =
      for {key, %ValueSpec{input_scope: :per_group} = spec} <- specs_map, into: %{} do
        seeded =
          Map.new(groups, fn group ->
            seed = get_in(initial, [key, group]) || spec.min || 0
            {group, clamp(seed, spec)}
          end)

        {key, seeded}
      end

    %__MODULE__{specs: specs_map, groups: groups, group_values: group_values}
  end

  @doc "The current per-group value, or `nil` if unknown."
  @spec get(t(), key(), group_id()) :: number() | nil
  def get(%__MODULE__{} = sim, key, group_id) do
    sim.group_values |> Map.get(key, %{}) |> Map.get(group_id)
  end

  @doc """
  Apply a single delta to one group's value for one `per_group` value, clamped to
  the value's bounds. Raises if `key` is not a known `per_group` value.
  """
  @spec apply_effect(t(), key(), group_id(), number()) :: t()
  def apply_effect(%__MODULE__{} = sim, key, group_id, delta) do
    spec = Map.fetch!(sim.specs, key)
    group_map = Map.fetch!(sim.group_values, key)
    updated = Map.put(group_map, group_id, clamp(Map.get(group_map, group_id, 0) + delta, spec))
    %{sim | group_values: Map.put(sim.group_values, key, updated)}
  end

  @doc "Apply a list of `{value_key, group_id, delta}` effects in order."
  @spec apply_effects(t(), [effect()]) :: t()
  def apply_effects(%__MODULE__{} = sim, effects) when is_list(effects) do
    Enum.reduce(effects, sim, fn {key, group_id, delta}, acc ->
      apply_effect(acc, key, group_id, delta)
    end)
  end

  @doc """
  Derive the global value for every value, `%{value_key => number | nil}`.

  A global is `nil` when it can't be computed yet — e.g. a `per_participant`
  value (no group votes here) or a `per_group` value with no groups.
  """
  @spec globals(t()) :: %{optional(key()) => number() | nil}
  def globals(%__MODULE__{} = sim) do
    Map.new(sim.specs, fn {key, spec} -> {key, global_for(sim, key, spec)} end)
  end

  defp global_for(sim, key, %ValueSpec{input_scope: :per_group} = spec) do
    values = sim.group_values |> Map.get(key, %{}) |> Map.values()

    case Formula.evaluate(spec.aggregation, values) do
      {:ok, number} -> number
      {:error, _reason} -> nil
    end
  end

  defp global_for(_sim, _key, _spec), do: nil

  defp clamp(value, %ValueSpec{min: lo, max: hi}) do
    value = if lo, do: max(value, lo), else: value
    if hi, do: min(value, hi), else: value
  end
end
