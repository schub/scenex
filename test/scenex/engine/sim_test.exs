defmodule Scenex.Engine.SimTest do
  use ExUnit.Case, async: true
  doctest Scenex.Engine.Sim

  alias Scenex.Engine.{Sim, ValueSpec}

  defp specs do
    [
      %ValueSpec{key: :stability, aggregation: "avg", min: 0, max: 100},
      %ValueSpec{key: :solidarity, aggregation: "min", min: 0, max: 100},
      %ValueSpec{
        key: :wellbeing,
        aggregation: "avg",
        min: 0,
        max: 100,
        input_scope: :per_participant
      }
    ]
  end

  defp groups, do: [:gov, :media, :citizens]

  defp initial do
    %{
      stability: %{gov: 60, media: 50, citizens: 40},
      solidarity: %{gov: 30, media: 70, citizens: 50}
    }
  end

  defp sim, do: Sim.new(specs(), groups(), initial())

  describe "new/3" do
    test "seeds per-group values from the initial map" do
      s = sim()
      assert Sim.get(s, :stability, :gov) == 60
      assert Sim.get(s, :solidarity, :media) == 70
    end

    test "does not seed per-participant values" do
      s = sim()
      refute Map.has_key?(s.group_values, :wellbeing)
      assert Sim.get(s, :wellbeing, :gov) == nil
    end

    test "defaults missing initial values to min (or 0) and clamps seeds to bounds" do
      s =
        Sim.new(
          [%ValueSpec{key: :risk, aggregation: "max", min: 10, max: 90}],
          [:a, :b],
          %{risk: %{a: 150}}
        )

      assert Sim.get(s, :risk, :a) == 90
      assert Sim.get(s, :risk, :b) == 10
    end
  end

  describe "globals/1" do
    test "derives globals via each value's aggregation formula" do
      assert Sim.globals(sim()) == %{
               stability: 50.0,
               solidarity: 30,
               wellbeing: nil
             }
    end

    test "a per-group global with no groups is nil" do
      s = Sim.new([%ValueSpec{key: :stability, aggregation: "avg"}], [])
      assert Sim.globals(s) == %{stability: nil}
    end
  end

  describe "apply_effect/4" do
    test "adds the delta and reflects in the global" do
      s = Sim.apply_effect(sim(), :stability, :gov, -10)
      assert Sim.get(s, :stability, :gov) == 50
      assert_in_delta Sim.globals(s).stability, (50 + 50 + 40) / 3, 1.0e-9
    end

    test "clamps to the value's max" do
      s = Sim.apply_effect(sim(), :stability, :gov, 999)
      assert Sim.get(s, :stability, :gov) == 100
    end

    test "clamps to the value's min" do
      s = Sim.apply_effect(sim(), :solidarity, :gov, -999)
      assert Sim.get(s, :solidarity, :gov) == 0
    end

    test "raises for an unknown value" do
      assert_raise KeyError, fn -> Sim.apply_effect(sim(), :nope, :gov, 1) end
    end
  end

  describe "record_tally/3" do
    test "the per-participant global becomes the count-weighted mean" do
      s = Sim.record_tally(sim(), :wellbeing, %{4 => 2, 3 => 1, 1 => 1})
      assert Sim.globals(s).wellbeing == 3.0
    end

    test "a later tally replaces the earlier one" do
      s =
        sim()
        |> Sim.record_tally(:wellbeing, %{4 => 10})
        |> Sim.record_tally(:wellbeing, %{2 => 3, 1 => 1})

      assert Sim.globals(s).wellbeing == 1.75
    end

    test "an all-zero tally yields a nil global" do
      s = Sim.record_tally(sim(), :wellbeing, %{4 => 0, 1 => 0})
      assert Sim.globals(s).wellbeing == nil
    end

    test "raises for a per-group value" do
      assert_raise MatchError, fn -> Sim.record_tally(sim(), :stability, %{4 => 1}) end
    end

    test "raises for an unknown value" do
      assert_raise KeyError, fn -> Sim.record_tally(sim(), :nope, %{4 => 1}) end
    end
  end

  describe "apply_effects/2" do
    test "applies a list of effects in order" do
      s = Sim.apply_effects(sim(), [{:stability, :gov, -10}, {:solidarity, :media, -25}])
      assert Sim.get(s, :stability, :gov) == 50
      assert Sim.get(s, :solidarity, :media) == 45
      # a decision shifts different groups differently:
      assert Sim.get(s, :stability, :media) == 50
    end
  end
end
