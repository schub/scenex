defmodule ScenexWeb.SessionQrPdfController do
  @moduledoc """
  Downloads every access QR code for a session — one per group table plus
  the projected display — as a single printable PDF handout. Same tokens,
  same URLs, same auth as the console's "Access & QR" section; this just
  gets them onto paper instead of a screen full of cards.
  """
  use ScenexWeb, :controller

  alias Scenex.{Authoring, Play}
  alias Scenex.I18n

  @margin 40
  @page_w 595
  @page_h 842
  @columns 2
  @card_gap 20
  @header_h 70
  @card_h 250
  @qr_size 150
  @label_h 34
  @url_h 22

  def download(conn, %{"id" => session_id}) do
    user = conn.assigns.current_scope.user
    session = Play.get_session!(session_id)

    case Authoring.get_scenario_for_user(session.scenario_id, user) do
      {scenario, role} when role in [:owner, :author] ->
        if Play.gm?(session, user, role) do
          send_pdf(conn, session, scenario)
        else
          deny(conn, session.scenario_id)
        end

      _ ->
        deny(conn, session.scenario_id)
    end
  end

  defp deny(conn, scenario_id) do
    conn
    |> put_flash(:error, "You cannot access this session.")
    |> redirect(to: ~p"/scenarios/#{scenario_id}/sessions")
  end

  defp send_pdf(conn, session, scenario) do
    tokens = Play.list_tokens(session)
    locale = session.locale || scenario.source_locale
    pdf = build_pdf(session, tokens, locale)

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename(session)}"))
    |> send_resp(200, pdf)
  end

  defp filename(session) do
    slug =
      session.label
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{if slug == "", do: "session", else: slug}-access-codes.pdf"
  end

  defp build_pdf(session, tokens, locale) do
    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(title: "#{session.label} — access codes", producer: "Scenex")
      |> draw_pages(tokens, session, locale)
      |> Pdf.export()
    end)
  end

  defp draw_pages(pdf, [], session, _locale), do: draw_header(pdf, session)

  defp draw_pages(pdf, tokens, session, locale) do
    tokens
    |> Enum.chunk_every(@columns * rows_per_page())
    |> Enum.with_index()
    |> Enum.reduce(pdf, fn {chunk, page_index}, pdf ->
      pdf = if page_index > 0, do: Pdf.add_page(pdf), else: pdf

      pdf
      |> draw_header(session)
      |> draw_cards(chunk, locale)
    end)
  end

  defp rows_per_page do
    usable = @page_h - @margin * 2 - @header_h
    max(div(usable + @card_gap, @card_h + @card_gap), 1)
  end

  defp draw_header(pdf, session) do
    top = @page_h - @margin

    pdf
    |> Pdf.set_font("Helvetica", 16, bold: true)
    |> Pdf.text_at({@margin, top - 18}, session.label)
    |> Pdf.set_font("Helvetica", 10)
    |> Pdf.set_fill_color(:black)
    |> Pdf.text_at({@margin, top - 36}, "Access codes — print, cut out, and hand out")
  end

  defp draw_cards(pdf, chunk, locale) do
    card_w = (@page_w - @margin * 2 - @card_gap * (@columns - 1)) / @columns
    grid_top = @page_h - @margin - @header_h

    chunk
    |> Enum.with_index()
    |> Enum.reduce(pdf, fn {token, i}, pdf ->
      row = div(i, @columns)
      col = rem(i, @columns)
      x = @margin + col * (card_w + @card_gap)
      card_top = grid_top - row * (@card_h + @card_gap)

      draw_card(pdf, token, locale, x, card_top, card_w)
    end)
  end

  defp draw_card(pdf, token, locale, x, top, card_w) do
    label = token_label(token, locale)
    url = token_url(token)
    qr_x = x + (card_w - @qr_size) / 2
    qr_y = top - @label_h - 6 - @qr_size

    pdf
    |> Pdf.set_stroke_color(:light_gray)
    |> Pdf.set_line_width(0.5)
    |> Pdf.rectangle({x, top - @card_h}, {card_w, @card_h})
    |> Pdf.stroke()
    |> Pdf.set_font("Helvetica", 12, bold: true)
    |> Pdf.set_fill_color(:black)
    |> wrap_text({x + 4, top - 6}, {card_w - 8, @label_h}, label, align: :center)
    |> draw_qr(url, {qr_x, qr_y})
    |> Pdf.set_font("Helvetica", 7)
    |> wrap_text({x + 4, qr_y - 6}, {card_w - 8, @url_h}, url, align: :center)
  end

  defp draw_qr(pdf, url, {x, y}) do
    png = url |> EQRCode.encode() |> EQRCode.png(width: 320)
    image = Pdf.create_image(pdf, {:binary, png})
    Pdf.draw_image(pdf, {x, y}, image, width: @qr_size, height: @qr_size)
  end

  # Author-controlled group names have no length limit — truncate instead of
  # crashing when a label or URL overruns its box (text_wrap! raises; this
  # doesn't).
  defp wrap_text(pdf, coords, dimensions, text, opts) do
    {pdf, _complete_or_remaining} = Pdf.text_wrap(pdf, coords, dimensions, text, opts)
    pdf
  end

  defp token_label(%{kind: :display}, _locale), do: "Projected display"

  defp token_label(%{kind: :group, group: group}, locale),
    do: I18n.t!(group.name, locale, default: group.handle)

  defp token_url(%{kind: :display, token: token}), do: url(~p"/display/#{token}")
  defp token_url(%{token: token}), do: url(~p"/play/#{token}")
end
