defmodule ScenexWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias ScenexWeb.Markdown

  defp html(markdown), do: markdown |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  test "renders markdown with hard line breaks" do
    out = html("**Pro:** order\nfast")
    assert out =~ "<strong>Pro:</strong>"
    assert out =~ "<br"
  end

  test "renders lists" do
    assert html("- one\n- two") =~ "<ul>"
  end

  test "nil and blank render nothing" do
    assert Markdown.to_html(nil) == nil
    assert Markdown.to_html("   ") == nil
  end

  test "raw HTML is shown as text, never executed" do
    # Inline HTML: Earmark escapes it itself.
    out = html("hi <script>alert(1)</script>")
    refute out =~ "<script>"
    assert out =~ "&lt;script"

    # Block-level HTML (line-leading tag) is Earmark's raw passthrough door —
    # our zero-width-space neutralization forces it down the text path.
    out = html("<script>alert(1)</script>")
    refute out =~ "<script>"
    assert out =~ "&lt;"
  end

  test "images stay images; video and audio references become players" do
    out = html("![poster](/media/abc/poster.png)")
    assert out =~ ~s(<img src="/media/abc/poster.png")

    out = html("![clip](/media/abc/clip.MP4)")
    assert out =~ ~s(<video controls preload="metadata" src="/media/abc/clip.MP4">)

    out = html("![jingle](/media/abc/jingle.mp3)")
    assert out =~ ~s(<audio controls)
  end
end
