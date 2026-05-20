defmodule Voria2Web.PageControllerTest do
  use Voria2Web.ConnCase

  import Voria2.MeasurementsHelpers

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "MeteoGargano"
    assert html =~ ~p"/blog"
  end

  test "GET / uses the first CDN body image as homepage card fallback", %{conn: conn} do
    previous_endpoint = Application.get_env(:voria2, :storage_public_endpoint)
    Application.put_env(:voria2, :storage_public_endpoint, "https://media.test")
    on_exit(fn -> Application.put_env(:voria2, :storage_public_endpoint, previous_endpoint) end)

    create_blog_article(
      title: "Homepage Fallback Article",
      slug: "homepage-fallback-article",
      body:
        ~s(<p>Intro</p><img src="https://media.test/blogcontent/files/home-cover.webp" alt="cover">),
      cover_image_url: nil,
      published: true,
      publishing_date: ~U[2026-05-01 10:00:00Z]
    )

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(src="https://media.test/blogcontent/files/home-cover.webp")
  end
end
