defmodule Scenex.I18nTest do
  use ExUnit.Case, async: true
  doctest Scenex.I18n

  alias Scenex.I18n

  describe "t/3" do
    test "returns the string for the requested locale" do
      assert I18n.t(%{"en" => "Stability", "de" => "Stabilität"}, "de") == "Stabilität"
      assert I18n.t(%{"en" => "Stability", "de" => "Stabilität"}, "en") == "Stability"
    end

    test "accepts atom locales" do
      assert I18n.t(%{"de" => "Stabilität"}, :de) == "Stabilität"
    end

    test "falls back to the :fallback locale" do
      assert I18n.t(%{"en" => "Stability"}, "de", fallback: "en") == "Stability"
      assert I18n.t(%{"en" => "Stability"}, :de, fallback: :en) == "Stability"
    end

    test "falls back to any present translation when locale and fallback are missing" do
      assert I18n.t(%{"pt" => "Estabilidade"}, "de", fallback: "en") == "Estabilidade"
    end

    test "treats blank/whitespace strings as absent" do
      assert I18n.t(%{"de" => "   ", "en" => "Stability"}, "de", fallback: "en") == "Stability"
      assert I18n.t(%{"de" => ""}, "de") == nil
    end

    test "returns nil for nil or fully-empty translations" do
      assert I18n.t(nil, "en") == nil
      assert I18n.t(%{}, "en") == nil
      assert I18n.t(%{"en" => "  "}, "en") == nil
    end
  end

  describe "t!/3" do
    test "returns the default when nothing is present" do
      assert I18n.t!(nil, "en") == ""
      assert I18n.t!(%{}, "en", default: "—") == "—"
    end

    test "returns the translation when present" do
      assert I18n.t!(%{"en" => "Stability"}, "en") == "Stability"
    end
  end
end
