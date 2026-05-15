defmodule Voria2Web.SitemapControllerTest do
  use Voria2Web.ConnCase, async: true

  import Voria2.MeasurementsHelpers

  test "GET /sitemap.xml lists public pages, active resources, and published articles", %{
    conn: conn
  } do
    user = create_user()

    installation = create_installation(user, name: "Active Installation")
    inactive_installation = create_installation(user, name: "Inactive Installation")
    webcam = create_webcam(installation, name: "Viewer Webcam")
    inactive_webcam = create_webcam(installation, name: "Hidden Webcam")

    published_article =
      create_blog_article(
        title: "Published Article",
        slug: "published-article",
        published: true
      )

    draft_article =
      create_blog_article(
        title: "Draft Article",
        slug: "draft-article",
        published: false
      )

    inactive_installation =
      inactive_installation
      |> Ash.Changeset.for_update(:update, %{is_active: false})
      |> Ash.update!(authorize?: false)

    inactive_webcam =
      inactive_webcam
      |> Ash.Changeset.for_update(:update, %{is_active: false})
      |> Ash.update!(authorize?: false)

    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)
    base_url = Voria2Web.Endpoint.url()

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert body =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)

    assert body =~ "<loc>#{base_url}/</loc>"
    assert body =~ "<loc>#{base_url}/associazione</loc>"
    assert body =~ "<loc>#{base_url}/blog</loc>"
    assert body =~ "<loc>#{base_url}/map</loc>"
    assert body =~ "<loc>#{base_url}/compare</loc>"
    assert body =~ "<loc>#{base_url}/webcams</loc>"

    assert body =~ "<loc>#{base_url}/installations/#{installation.id}</loc>"
    refute body =~ "<loc>#{base_url}/installations/#{inactive_installation.id}</loc>"

    assert body =~ "<loc>#{base_url}/webcams/#{webcam.id}/viewer</loc>"
    refute body =~ "<loc>#{base_url}/webcams/#{webcam.id}</loc>"
    refute body =~ "<loc>#{base_url}/webcams/#{inactive_webcam.id}/viewer</loc>"

    assert body =~ "<loc>#{base_url}/blog/#{published_article.slug}</loc>"
    refute body =~ "<loc>#{base_url}/blog/#{draft_article.slug}</loc>"

    refute body =~ "<loc>#{base_url}/preferences</loc>"
    refute body =~ "/dailylog/"

    assert body =~ DateTime.to_iso8601(installation.updated_at)
    assert body =~ DateTime.to_iso8601(webcam.updated_at)
    assert body =~ DateTime.to_iso8601(published_article.updated_at)
  end
end
