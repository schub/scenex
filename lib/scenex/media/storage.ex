defmodule Scenex.Media.Storage do
  @moduledoc """
  Where media bytes live, behind a minimal behaviour so the backend can be
  swapped (local disk today; an S3-compatible store like Garage later)
  without touching the context, the controller contract, or — crucially —
  any public URL an author has pasted into content.
  """

  @callback put(key :: String.t(), source_path :: Path.t()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok

  def put(key, source_path), do: impl().put(key, source_path)
  def delete(key), do: impl().delete(key)

  defp impl do
    Application.fetch_env!(:scenex, Scenex.Media)[:storage] || Scenex.Media.Storage.Local
  end
end
