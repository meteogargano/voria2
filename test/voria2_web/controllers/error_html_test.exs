defmodule Voria2Web.ErrorHTMLTest do
  use Voria2Web.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  setup do
    locale = Gettext.get_locale(Voria2Web.Gettext)
    on_exit(fn -> Gettext.put_locale(Voria2Web.Gettext, locale) end)
  end

  test "renders 404.html" do
    html = render_to_string(Voria2Web.ErrorHTML, "404", "html", [])

    assert html =~ "Page not found"
    assert html =~ "Back to home"
    assert html =~ "Associazione"
  end

  test "renders 500.html" do
    html = render_to_string(Voria2Web.ErrorHTML, "500", "html", [])

    assert html =~ "Something went wrong"
    assert html =~ "Back to home"
    assert html =~ "Associazione"
  end

  test "renders localized copy when locale is changed" do
    Gettext.put_locale(Voria2Web.Gettext, "it")

    html = render_to_string(Voria2Web.ErrorHTML, "404", "html", [])

    assert html =~ "Pagina non trovata"
    assert html =~ "Torna alla home"
  end
end
