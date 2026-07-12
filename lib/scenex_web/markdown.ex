defmodule ScenexWeb.Markdown do
  @moduledoc """
  Renders authored content snippets (markdown) to safe HTML for the play
  views, with media embeds: an image-syntax reference to a video or audio
  file (`![...](/media/...mp4)`) becomes a `<video>` / `<audio>` player.

  Safety by construction: Earmark escapes all *inline* HTML itself; the one
  raw-HTML door it leaves open is *block-level* HTML (a line starting with
  `<`). We slip a zero-width space behind any line-leading `<` before
  parsing, so such lines are treated as text and escaped like everything
  else — the output can only contain tags the renderer itself generates.
  Single newlines become line breaks (authored content relies on them).
  """

  @video_exts ~w(.mp4 .webm .mov .m4v)
  @audio_exts ~w(.mp3 .ogg .oga .wav .m4a .aac .flac)

  @doc "Markdown → `{:safe, html}` for HEEx interpolation; nil/blank → nil."
  def to_html(nil), do: nil

  def to_html(markdown) when is_binary(markdown) do
    if String.trim(markdown) == "" do
      nil
    else
      markdown
      |> String.replace(~r/^([ \t]{0,3})</m, "\\1<​")
      |> Earmark.as_html!(breaks: true, compact_output: false)
      |> embed_media()
      |> Phoenix.HTML.raw()
    end
  end

  # Earmark renders `![alt](src)` as `<img src="..." alt="..." />` — rewrite
  # references to video/audio files into players. The attribute values are
  # entity-escaped by Earmark, so matching on the quoted src is safe.
  defp embed_media(html) do
    Regex.replace(~r/<img src="([^"]+)" alt="[^"]*"\s*\/?>/, html, fn whole, src ->
      cond do
        media?(src, @video_exts) ->
          ~s(<video controls preload="metadata" src="#{src}"></video>)

        media?(src, @audio_exts) ->
          ~s(<audio controls preload="metadata" src="#{src}"></audio>)

        true ->
          whole
      end
    end)
  end

  defp media?(src, exts) do
    ext = src |> String.downcase() |> Path.extname()
    ext in exts
  end
end
