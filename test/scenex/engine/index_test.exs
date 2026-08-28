defmodule Scenex.Engine.IndexTest do
  use ExUnit.Case, async: true
  doctest Scenex.Engine.Index

  alias Scenex.Engine.Index

  describe "evaluate" do
    test "reads a value's global back by key" do
      assert Index.evaluate("stability", %{"stability" => 7}) == {:ok, 7}
    end

    test "weights and combines several values" do
      ctx = %{"stability" => 3, "resources" => 4}
      assert Index.evaluate("2*stability + 3*resources", ctx) == {:ok, 18}
    end

    test "honours precedence and parentheses" do
      ctx = %{"a" => 6, "b" => 2}
      assert Index.evaluate("a + b * 2", ctx) == {:ok, 10}
      assert Index.evaluate("(a + b) * 2", ctx) == {:ok, 16}
    end

    test "supports unary minus and normalising by literals" do
      assert Index.evaluate("-stability", %{"stability" => 5}) == {:ok, -5}

      assert Index.evaluate("stability/10 + resources/100", %{"stability" => 5, "resources" => 50}) ==
               {:ok, 1.0}
    end

    test "a referenced value missing from the context is an error, not a crash" do
      assert Index.evaluate("stability + trust", %{"stability" => 5}) ==
               {:error, {:unknown_value, "trust"}}
    end

    test "division by zero is reported" do
      assert Index.evaluate("stability / 0", %{"stability" => 5}) == {:error, :division_by_zero}
    end
  end

  describe "validate" do
    test "accepts syntactically valid formulas" do
      assert Index.validate("2*stability + resources") == :ok
    end

    test "rejects malformed syntax" do
      assert {:error, _} = Index.validate("2 * ")
      assert {:error, _} = Index.validate("(stability + resources")
      assert {:error, _} = Index.validate("")
    end

    test "with :keys, rejects references to unknown value keys" do
      assert Index.validate("stability + resources", keys: ["stability", "resources"]) == :ok

      assert Index.validate("stability + trust", keys: ["stability", "resources"]) ==
               {:error, {:unknown_value_key, "trust"}}
    end
  end

  describe "references" do
    test "lists the distinct value keys used" do
      assert Index.references("2*stability + stability - resources") ==
               ["stability", "resources"]
    end
  end
end
