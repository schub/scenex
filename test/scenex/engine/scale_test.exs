defmodule Scenex.Engine.ScaleTest do
  use ExUnit.Case, async: true
  doctest Scenex.Engine.Scale

  alias Scenex.Engine.Scale

  describe "label/4" do
    @labels ["In Bloom", "Resilient", "Fragile", "Critical", "Breakdown"]

    test "five equal bands over 0..100" do
      assert Scale.label(100.0, 0.0, 100.0, @labels) == "In Bloom"
      assert Scale.label(85.0, 0.0, 100.0, @labels) == "In Bloom"
      assert Scale.label(75.0, 0.0, 100.0, @labels) == "Resilient"
      assert Scale.label(50.0, 0.0, 100.0, @labels) == "Fragile"
      assert Scale.label(25.0, 0.0, 100.0, @labels) == "Critical"
      assert Scale.label(0.0, 0.0, 100.0, @labels) == "Breakdown"
    end

    test "four equal bands, e.g. well-being over 1..4" do
      moods = ["Very happy", "Happy", "OK", "Not Happy"]

      assert Scale.label(4.0, 1.0, 4.0, moods) == "Very happy"
      assert Scale.label(3.0, 1.0, 4.0, moods) == "Happy"
      assert Scale.label(2.0, 1.0, 4.0, moods) == "OK"
      assert Scale.label(1.0, 1.0, 4.0, moods) == "Not Happy"
    end

    test "out-of-range values clamp to the nearest end" do
      assert Scale.label(999.0, 0.0, 100.0, @labels) == "In Bloom"
      assert Scale.label(-999.0, 0.0, 100.0, @labels) == "Breakdown"
    end

    test "a degenerate min == max range reads as the best label" do
      assert Scale.label(5.0, 5.0, 5.0, @labels) == "In Bloom"
    end

    test "a single label always applies" do
      assert Scale.label(0.0, 0.0, 10.0, ["Only"]) == "Only"
      assert Scale.label(10.0, 0.0, 10.0, ["Only"]) == "Only"
    end
  end

  describe "index/4" do
    test "0-based, 0 = best (nearest max)" do
      assert Scale.index(100.0, 0.0, 100.0, 4) == 0
      assert Scale.index(0.0, 0.0, 100.0, 4) == 3
      assert Scale.index(50.0, 0.0, 100.0, 4) in [1, 2]
    end

    test "out-of-range values clamp to the nearest end" do
      assert Scale.index(999.0, 0.0, 100.0, 5) == 0
      assert Scale.index(-999.0, 0.0, 100.0, 5) == 4
    end
  end

  describe "position/3" do
    test "maps min..max onto 0.0..1.0" do
      assert Scale.position(0.0, 0.0, 10.0) == 0.0
      assert Scale.position(10.0, 0.0, 10.0) == 1.0
      assert Scale.position(5.0, 0.0, 10.0) == 0.5
    end

    test "clamps out-of-range values" do
      assert Scale.position(-5.0, 0.0, 10.0) == 0.0
      assert Scale.position(15.0, 0.0, 10.0) == 1.0
    end

    test "a degenerate min == max range is always 1.0" do
      assert Scale.position(5.0, 5.0, 5.0) == 1.0
    end
  end
end
