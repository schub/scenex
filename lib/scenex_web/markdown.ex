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

  @doc """
  Markdown → `{:safe, html}` for HEEx interpolation; nil/blank → nil.

  `mode: :narrative` (default) is the in-story case — a video embed gets
  visible `controls` for a GM/player to start manually. `mode: :page` is a
  pre-authored full-screen scoreboard slide instead: video plays once on
  its own — `autoplay`, `muted` (required by browsers for autoplay to fire
  at all), no `controls`, no loop.
  """
  def to_html(markdown, opts \\ [])

  def to_html(nil, _opts), do: nil

  def to_html(markdown, opts) when is_binary(markdown) do
    if String.trim(markdown) == "" do
      nil
    else
      mode = Keyword.get(opts, :mode, :narrative)

      markdown
      |> String.replace(~r/^([ \t]{0,3})</m, "\\1<​")
      |> Earmark.as_html!(breaks: true, compact_output: false)
      |> embed_media(mode)
      |> Phoenix.HTML.raw()
    end
  end

  # Earmark renders `![alt](src)` as `<img src="..." alt="..." />` — rewrite
  # references to video/audio files into players. The attribute values are
  # entity-escaped by Earmark, so matching on the quoted src is safe.
  defp embed_media(html, mode) do
    Regex.replace(~r/<img src="([^"]+)" alt="[^"]*"\s*\/?>/, html, fn whole, src ->
      cond do
        media?(src, @video_exts) ->
          video_tag(src, mode)

        media?(src, @audio_exts) ->
          ~s(<audio controls preload="metadata" src="#{src}"></audio>)

        true ->
          whole
      end
    end)
  end

  # A stable id (derived from src, so it's the same across renders of the
  # same content) keeps LiveView's diffing from ever treating this as a new
  # element on an unrelated re-render (e.g. a display's once-a-second clock
  # tick) — without one, a periodic patch can silently replace the node,
  # which restarts playback from zero and looks exactly like a manual loop.
  defp video_tag(src, mode) do
    id = "video-#{:erlang.phash2(src)}"

    case mode do
      :page -> ~s(<video id="#{id}" autoplay muted playsinline src="#{src}"></video>)
      :narrative -> ~s(<video id="#{id}" controls preload="metadata" src="#{src}"></video>)
    end
  end

  defp media?(src, exts) do
    ext = src |> String.downcase() |> Path.extname()
    ext in exts
  end
end
