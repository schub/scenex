defmodule Scenex.I18n do
  @moduledoc """
  Helpers for **localized content fields**.

  Two kinds of i18n live in Scenex:

    * UI chrome (buttons, labels, errors) → handled by Gettext.
    * Authored game *content* (value names, group names, event narratives,
      decision texts, ...) → stored in the database as a plain map of
      `locale => string`, e.g. `%{"en" => "Stability", "de" => "Stabilität"}`.

  This module only concerns the second kind. Content is rendered **per viewer**
  in their chosen locale, falling back to the definition's source locale, then to
  any translation that exists, so a partially-translated game never shows blanks.

  The event log (Layer 3) stays language-neutral: it records *which* decision by
  id; each viewer renders the text through `t/3`.
  """

  @type translations :: %{optional(String.t()) => String.t()} | nil

  @doc """
  Fetch the localized string for `locale`.

  Resolution order:

    1. the requested `locale`
    2. the `:fallback` locale (typically the definition's source locale)
    3. any present translation
    4. `nil`

  Blank/whitespace-only strings are treated as absent. `locale` and `:fallback`
  may be atoms or strings.

  ## Examples

      iex> Scenex.I18n.t(%{"en" => "Stability", "de" => "Stabilität"}, "de")
      "Stabilität"

      iex> Scenex.I18n.t(%{"en" => "Stability"}, "de", fallback: "en")
      "Stability"

      iex> Scenex.I18n.t(%{"en" => "  "}, "de", fallback: "en")
      nil
  """
  @spec t(translations(), atom() | String.t(), keyword()) :: String.t() | nil
  def t(translations, locale, opts \\ [])
  def t(nil, _locale, _opts), do: nil

  def t(translations, locale, opts) when is_map(translations) do
    locale = to_string(locale)
    fallback = opts |> Keyword.get(:fallback) |> normalize_locale()

    preferred =
      Enum.find_value([locale, fallback], fn
        nil -> nil
        loc -> present(translations[loc])
      end)

    preferred || translations |> Map.values() |> Enum.find_value(&present/1)
  end

  @doc """
  Like `t/3` but returns `default` (default `""`) instead of `nil` when no
  translation is present. Handy in templates.
  """
  @spec t!(translations(), atom() | String.t(), keyword()) :: String.t()
  def t!(translations, locale, opts \\ []) do
    {default, opts} = Keyword.pop(opts, :default, "")
    t(translations, locale, opts) || default
  end

  @doc "Whether a translations map contains at least one non-blank value."
  @spec present?(translations()) :: boolean()
  def present?(translations) when is_map(translations) do
    translations |> Map.values() |> Enum.any?(&(present(&1) != nil))
  end

  def present?(_), do: false

  defp normalize_locale(nil), do: nil
  defp normalize_locale(locale), do: to_string(locale)

  defp present(nil), do: nil

  defp present(str) when is_binary(str) do
    if String.trim(str) == "", do: nil, else: str
  end

  defp present(_), do: nil
end
