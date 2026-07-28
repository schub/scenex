defmodule Scenex.Authoring.Validators do
  @moduledoc "Shared changeset validators for Authoring schemas."

  import Ecto.Changeset

  alias Scenex.I18n

  @doc """
  Validate that a localized (`jsonb` map) field has at least one non-blank
  translation. A partially-translated field is fine; a fully-empty one is not.
  """
  def validate_localized_required(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if I18n.present?(value), do: [], else: [{field, "can't be blank"}]
    end)
  end

  @doc """
  Validate a condition field via `Scenex.Engine.Condition.validate/2`.

  Options are passed through: `:allow_self` and `:keys` (known value keys).
  """
  def validate_condition(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn ^field, condition ->
      case Scenex.Engine.Condition.validate(condition, opts) do
        :ok -> []
        {:error, reason} -> [{field, "is not a valid condition (#{format_reason(reason)})"}]
      end
    end)
  end

  @doc "Validate a formula field via `Scenex.Engine.Formula.validate/1`."
  def validate_formula(changeset, field) do
    validate_change(changeset, field, fn ^field, formula ->
      case Scenex.Engine.Formula.validate(formula) do
        :ok -> []
        {:error, reason} -> [{field, "is not a valid formula (#{inspect(reason)})"}]
      end
    end)
  end

  @doc """
  Validate that `min_field < max_field` when both are present. Skips the
  check entirely if either is nil (an incomplete range isn't this
  validator's problem — pair it with `validate_required` where that matters).
  """
  def validate_min_max(changeset, min_field, max_field) do
    min = get_field(changeset, min_field)
    max = get_field(changeset, max_field)

    if is_number(min) and is_number(max) and min > max do
      add_error(changeset, max_field, "must be greater than or equal to #{min_field}")
    else
      changeset
    end
  end

  defp format_reason(:missing_comparison), do: "needs a comparison, e.g. self(key) >= 3"
  defp format_reason(:multiple_comparisons), do: "only one comparison is allowed"
  defp format_reason(:self_not_allowed), do: "self(...) is not allowed here"
  defp format_reason({:unknown_value_key, key}), do: "unknown value key #{inspect(key)}"
  defp format_reason({:unknown_reference, name}), do: "unknown reference #{inspect(name)}"
  defp format_reason(reason), do: inspect(reason)
end
