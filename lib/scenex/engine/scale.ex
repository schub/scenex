defmodule Scenex.Engine.Scale do
  @moduledoc """
  Maps a number on a `min..max` range to one of N equal-width bands, each
  carrying a label — e.g. a democracy score's five states, or a well-being
  mean's four moods. Pure and self-contained.

  `min` is the worst end of the range, `max` the best end (matching how the
  rest of the engine treats value bounds); `labels` are given **best to
  worst**, matching how they read on screen.

  ## Examples

      iex> Scenex.Engine.Scale.label(9.0, 0.0, 10.0, ["Good", "Mid", "Bad"])
      "Good"

      iex> Scenex.Engine.Scale.label(5.0, 0.0, 10.0, ["Good", "Mid", "Bad"])
      "Mid"

      iex> Scenex.Engine.Scale.label(0.0, 0.0, 10.0, ["Good", "Mid", "Bad"])
      "Bad"

      iex> Scenex.Engine.Scale.position(7.5, 0.0, 10.0)
      0.75

      iex> Scenex.Engine.Scale.index(9.0, 0.0, 10.0, 3)
      0
  """

  @doc """
  The band label for `value` on `min..max`, from `labels` given best-to-worst.
  Out-of-range values clamp to the nearest end; a degenerate `min == max`
  range always reads as the best label.
  """
  @spec label(number(), number(), number(), [String.t()]) :: String.t()
  def label(value, min, max, [_ | _] = labels) do
    Enum.at(labels, index(value, min, max, length(labels)))
  end

  @doc """
  Which of `band_count` equal-width bands (0 = best, `band_count - 1` =
  worst) `value` falls into on `min..max`. The building block behind
  `label/4` — use this directly to pick something other than a text label
  for a band, e.g. an emoji.
  """
  @spec index(number(), number(), number(), pos_integer()) :: non_neg_integer()
  def index(value, min, max, band_count) when band_count > 0 do
    from_best = trunc((1.0 - position(value, min, max)) * band_count)
    from_best |> max(0) |> min(band_count - 1)
  end

  @doc "Where `value` falls on `min..max`, clamped to `0.0..1.0` (0 = min, 1 = max)."
  @spec position(number(), number(), number()) :: float()
  def position(_value, min, max) when min == max, do: 1.0

  def position(value, min, max) do
    ((value - min) / (max - min) * 1.0)
    |> max(0.0)
    |> min(1.0)
  end
end
