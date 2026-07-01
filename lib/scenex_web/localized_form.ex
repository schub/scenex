defmodule ScenexWeb.LocalizedForm do
  @moduledoc """
  Helpers for editing localized (`jsonb` map) content fields one locale at a time.

  The CMS edits content in a selected working locale. A form submits only that
  locale's value for a localized field (e.g. `%{"en" => "Stability"}`); these
  helpers merge it back into the existing translations so the other locales are
  preserved, and read the current locale's value for display.
  """

  alias Scenex.I18n

  @doc """
  Merge submitted per-locale values for `fields` into the existing struct's maps,
  so untouched locales survive. `params` and result use string keys.
  """
  def merge(params, data, fields) when is_map(params) do
    Enum.reduce(fields, params, fn field, acc ->
      key = to_string(field)

      case Map.get(acc, key) do
        submitted when is_map(submitted) ->
          existing = Map.get(data, field) || %{}
          Map.put(acc, key, Map.merge(existing, submitted))

        _ ->
          acc
      end
    end)
  end

  @doc "The current localized value for a form-backed field, for input display."
  def value(form, field, locale) do
    raw = form.params[to_string(field)] || Map.get(form.data, field)
    I18n.t(raw, locale) || ""
  end
end
