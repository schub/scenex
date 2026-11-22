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

  describe "locale_name/1" do
    test "returns the native name for a supported code" do
      assert I18n.locale_name("de") == "Deutsch"
      assert I18n.locale_name(:no) == "Norsk"
    end

    test "returns the code itself when unknown" do
      assert I18n.locale_name("xx") == "xx"
    end
  end
end
