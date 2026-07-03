defmodule Scenex.Engine.ConditionTest do
  use ExUnit.Case, async: true

  alias Scenex.Engine.Condition

  doctest Scenex.Engine.Condition

  @ctx %{
    self: %{"resources" => 5, "stability" => 7.0, "solidarity" => 3.0},
    global: %{"risk" => 8.5, "stability" => 5.33}
  }

  describe "parse/1" do
    test "parses a simple comparison" do
      assert {:ok, {:cmp, :gte, {:ref, :self, "resources"}, {:num, 3}}} =
               Condition.parse("self(resources) >= 3")
    end

    test "parses all comparators" do
      for {op_string, op} <- [
            {">=", :gte},
            {"<=", :lte},
            {">", :gt},
            {"<", :lt},
            {"==", :eq},
            {"!=", :neq}
          ] do
        assert {:ok, {:cmp, ^op, _, _}} = Condition.parse("global(risk) #{op_string} 5")
      end
    end

    test "parses arithmetic with precedence and parentheses" do
      assert {:ok, {:cmp, :gt, left, {:num, 5}}} =
               Condition.parse("(self(stability) + self(solidarity)) / 2 > 5")

      assert {:binop, :divide, {:binop, :plus, _, _}, {:num, 2}} = left
    end

    test "parses unary minus and floats" do
      assert {:ok, {:cmp, :lt, {:neg, {:ref, :global, "risk"}}, {:neg, {:num, 2.5}}}} =
               Condition.parse("-global(risk) < -2.5")
    end

    test "rejects a bare expression" do
      assert {:error, :missing_comparison} = Condition.parse("self(resources) + 3")
    end

    test "rejects chained comparisons" do
      assert {:error, :multiple_comparisons} = Condition.parse("1 > 2 > 3")
    end

    test "rejects unknown references" do
      assert {:error, {:unknown_reference, "sums"}} = Condition.parse("sums(risk) > 1")
    end

    test "rejects malformed references" do
      assert {:error, {:invalid_reference, "self"}} = Condition.parse("self > 1")
      assert {:error, {:invalid_reference, "global"}} = Condition.parse("global() > 1")
    end

    test "rejects unbalanced parentheses and garbage" do
      assert {:error, :missing_closing_paren} = Condition.parse("(self(a) > 1")
      assert {:error, :invalid_syntax} = Condition.parse("self(a) = 1")
      assert {:error, :invalid_syntax} = Condition.parse("")
      assert {:error, :unexpected_end} = Condition.parse("self(a) >")
    end
  end

  describe "validate/2" do
    test "accepts a valid condition" do
      assert :ok = Condition.validate("self(resources) >= 3")
    end

    test "allow_self: false rejects self references" do
      assert {:error, :self_not_allowed} =
               Condition.validate("self(resources) >= 3", allow_self: false)

      assert :ok = Condition.validate("global(risk) >= 3", allow_self: false)
    end

    test "keys: restricts references to known value keys" do
      assert :ok = Condition.validate("self(resources) > 1", keys: ["resources", "risk"])

      assert {:error, {:unknown_value_key, "wealth"}} =
               Condition.validate("self(wealth) > 1", keys: ["resources", "risk"])
    end
  end

  describe "evaluate/2" do
    test "evaluates references from both scopes" do
      assert {:ok, true} = Condition.evaluate("self(resources) >= 3", @ctx)
      assert {:ok, false} = Condition.evaluate("global(risk) < 8", @ctx)
      assert {:ok, true} = Condition.evaluate("self(stability) > global(stability)", @ctx)
    end

    test "evaluates arithmetic" do
      assert {:ok, true} =
               Condition.evaluate("(self(stability) + self(solidarity)) / 2 == 5", @ctx)

      assert {:ok, true} = Condition.evaluate("self(resources) * 2 - 1 != 10", @ctx)
    end

    test "integer and float comparisons interoperate" do
      assert {:ok, true} = Condition.evaluate("self(stability) == 7", @ctx)
    end

    test "errors on a scope missing from the context" do
      assert {:error, {:scope_unavailable, :self}} =
               Condition.evaluate("self(resources) > 1", %{global: %{"risk" => 1}})
    end

    test "errors on an unknown value key" do
      assert {:error, {:unknown_value, :global, "wealth"}} =
               Condition.evaluate("global(wealth) > 1", @ctx)
    end

    test "errors on a nil value" do
      assert {:error, {:no_value, :global, "risk"}} =
               Condition.evaluate("global(risk) > 1", %{global: %{"risk" => nil}})
    end

    test "errors on division by zero" do
      assert {:error, :division_by_zero} = Condition.evaluate("1 / 0 > 1", @ctx)
    end

    test "accepts a pre-parsed AST" do
      {:ok, ast} = Condition.parse("self(resources) >= 3")
      assert {:ok, true} = Condition.evaluate(ast, @ctx)
    end
  end

  describe "references/1" do
    test "collects unique references" do
      assert {:ok, ast} = Condition.parse("self(a) + self(a) > global(b)")
      assert Condition.references(ast) == [{:self, "a"}, {:global, "b"}]
    end

    test "works on strings and propagates parse errors" do
      assert Condition.references("self(a) > 1") == [{:self, "a"}]
      assert {:error, :missing_comparison} = Condition.references("self(a)")
    end
  end
end
