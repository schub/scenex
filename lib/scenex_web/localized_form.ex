defmodule ScenexWeb.LocalizedForm do
  @moduledoc """
  Helpers for editing localized (`jsonb` map) content fields one locale at a time.

  The CMS edits content in a selected working locale; a form's inputs carry
  only that locale's values. Drafts are **tracked** across locale switches
  (`track/2` deep-merges each change event into the form params, so switching
  the working locale never loses what was typed), read back per exact locale
  (`value/3` — deliberately no cross-locale fallback: an empty Polish field
  must look empty, not show the English text), and **merged** into the saved
  maps on submit (`merge/3`), so one save persists every locale touched and
  untouched locales survive.
  """

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

  @doc """
  Deep-merge one change event's params into the previously tracked ones:
  map values (the per-locale fields) merge, everything else is replaced.
  Keeps drafts for locales whose inputs are currently not on the page.
  """
  def track(previous_params, new_params) do
    Map.merge(previous_params, new_params, fn _key, old, new ->
      if is_map(old) and is_map(new), do: Map.merge(old, new), else: new
    end)
  end

  @doc """
  The current locale's value for a form-backed field: the tracked draft if
  present, else the saved translation — never another locale's text.
  """
  def value(form, field, locale) do
    locale = to_string(locale)
    drafts = form.params[to_string(field)] || %{}
    saved = Map.get(form.data, field) || %{}
    Map.get(drafts, locale) || Map.get(saved, locale) || ""
  end
end
