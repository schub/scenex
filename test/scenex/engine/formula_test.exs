defmodule Scenex.Engine.FormulaTest do
  use ExUnit.Case, async: true
  doctest Scenex.Engine.Formula

  alias Scenex.Engine.Formula

  describe "aggregations" do
    test "min / max / sum / avg" do
      assert Formula.evaluate("min", [10, 20, 30]) == {:ok, 10}
      assert Formula.evaluate("max", [10, 20, 30]) == {:ok, 30}
      assert Formula.evaluate("sum", [10, 20, 30]) == {:ok, 60}
      assert Formula.evaluate("avg", [10, 20, 30]) == {:ok, 20.0}
      assert Formula.evaluate("average", [10, 20, 30]) == {:ok, 20.0}
    end

    test "median for odd and even counts" do
      assert Formula.evaluate("median", [3, 1, 2]) == {:ok, 2}
      assert Formula.evaluate("median", [1, 2, 3, 4]) == {:ok, 2.5}
    end

    test "is case-insensitive" do
      assert Formula.evaluate("AVG", [2, 4]) == {:ok, 3.0}
    end

    test "empty value list is an error" do
      assert Formula.evaluate("avg", []) == {:error, :empty}
      assert Formula.evaluate("min", []) == {:error, :empty}
    end
  end

  describe "arithmetic and precedence" do
    test "combines aggregations with operators" do
      assert Formula.evaluate("(avg + min) / 2", [10, 20, 30]) == {:ok, 15.0}
      assert Formula.evaluate("max - min", [10, 20, 30]) == {:ok, 20}
      assert Formula.evaluate("sum / 2", [10, 20, 30]) == {:ok, 30.0}
    end

    test "respects multiplication before addition" do
      assert Formula.evaluate("2 + 3 * 4", []) == {:ok, 14}
      assert Formula.evaluate("(2 + 3) * 4", []) == {:ok, 20}
    end

    test "numeric literals and floats" do
      assert Formula.evaluate("42", []) == {:ok, 42}
      assert Formula.evaluate("1.5 * 2", []) == {:ok, 3.0}
    end

    test "unary minus" do
      assert Formula.evaluate("-min", [5, 9]) == {:ok, -5}
      assert Formula.evaluate("0 - max", [5, 9]) == {:ok, -9}
    end

    test "division by zero is an error" do
      assert Formula.evaluate("10 / 0", []) == {:error, :division_by_zero}
      assert Formula.evaluate("sum / 0", [1, 2]) == {:error, :division_by_zero}
    end
  end

  describe "validate/1" do
    test "accepts valid formulas" do
      assert Formula.validate("avg") == :ok
      assert Formula.validate("(max + min) / 2") == :ok
      assert Formula.validate("median * 1.0") == :ok
    end

    test "rejects unknown aggregations" do
      assert Formula.validate("foo") == {:error, {:unknown_aggregation, "foo"}}
    end

    test "rejects invalid characters" do
      assert Formula.validate("avg & min") == {:error, :invalid_syntax}
      assert Formula.validate("") == {:error, :invalid_syntax}
    end

    test "rejects unbalanced parentheses" do
      assert Formula.validate("(avg + min") == {:error, :missing_closing_paren}
    end

    test "rejects dangling operators" do
      assert match?({:error, _}, Formula.validate("avg +"))
      assert match?({:error, _}, Formula.validate("* avg"))
    end
  end
end
