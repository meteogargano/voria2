defmodule Voria2Web.BlogControllerTest do
  use Voria2Web.ConnCase, async: true

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Voria2.MeasurementsHelpers

  @past_publication ~U[2026-05-01 10:00:00Z]
  @future_publication ~U[2026-12-01 10:00:00Z]

  defp title_position(html, title) do
    case :binary.match(html, title) do
      {position, _length} -> position
      :nomatch -> flunk("expected to find #{inspect(title)} in response")
    end
  end

  test "GET /blog lists only published articles and includes navbar link", %{conn: conn} do
    published =
      create_blog_article(
        title: "Storm Update",
        slug: "storm-update",
        body: "<p>Published body</p>",
        published: true,
        publishing_date: @past_publication
      )

    create_blog_article(title: "Draft Article", slug: "draft-article", published: false)

    create_blog_article(
      title: "Scheduled Article",
      slug: "scheduled-article",
      published: true,
      publishing_date: @future_publication
    )

    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)

    assert html =~ "Blog"
    assert html =~ published.title
    assert html =~ ~p"/blog/#{published.slug}"
    assert html =~ ~p"/blog"
    refute html =~ "Draft Article"
  end

  test "GET /blog sanitizes and truncates article excerpts", %{conn: conn} do
    body =
      "<p>Hello&nbsp;<strong>world</strong><script>alert(1)</script></p>" <>
        String.duplicate("a", 205) <>
        " &lt;em&gt;later&lt;/em&gt;"

    create_blog_article(
      title: "Excerpt Test",
      slug: "excerpt-test",
      body: body,
      published: true,
      publishing_date: @past_publication
    )

    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)

    assert html =~ "Hello world"
    refute html =~ "&nbsp;"
    refute html =~ "alert(1)"
    refute html =~ "&lt;em&gt;"
    refute html =~ "<em>later</em>"

    assert html =~
             "Hello world " <> String.duplicate("a", 187) <> "…"
  end

  test "GET /blog filters by title query", %{conn: conn} do
    create_blog_article(
      title: "Storm Update",
      slug: "storm-update",
      published: true,
      publishing_date: ~U[2026-05-02 09:00:00Z]
    )

    create_blog_article(
      title: "Rain Report",
      slug: "rain-report",
      published: true,
      publishing_date: @past_publication
    )

    conn = get(conn, ~p"/blog?q=storm")
    html = html_response(conn, 200)

    assert html =~ "Storm Update"
    refute html =~ "Rain Report"
  end

  test "GET /blog filters by category", %{conn: conn} do
    weather = create_blog_category(name: "Weather")
    climate = create_blog_category(name: "Climate")

    create_blog_article(
      title: "Storm Update",
      slug: "storm-update",
      published: true,
      publishing_date: @past_publication,
      category_ids: [weather.id]
    )

    create_blog_article(
      title: "Climate Brief",
      slug: "climate-brief",
      published: true,
      publishing_date: @past_publication,
      category_ids: [climate.id]
    )

    conn = get(conn, ~p"/blog?category=Weather")
    html = html_response(conn, 200)

    assert html =~ "Storm Update"
    refute html =~ "Climate Brief"
  end

  test "GET /blog/:slug renders a published article", %{conn: conn} do
    category = create_blog_category(name: "Weather")

    article =
      create_blog_article(
        title: "Storm Update",
        slug: "storm-update",
        body: "<p>Wind is increasing.</p>",
        cover_image_url: "https://cdn.example.com/storm.jpg",
        published: true,
        publishing_date: @past_publication,
        category_ids: [category.id]
      )

    conn = get(conn, ~p"/blog/#{article.slug}")
    html = html_response(conn, 200)

    assert html =~ article.title
    assert html =~ "Wind is increasing."
    assert html =~ article.cover_image_url
    assert html =~ "Weather"
    refute html =~ "Draft preview"
    refute html =~ "Scheduled preview"
    assert html =~ DateTime.to_iso8601(article.publishing_date)
  end

  test "GET /blog/:slug hides the cover block when no thumbnail is set", %{conn: conn} do
    article =
      create_blog_article(
        title: "No Cover Article",
        slug: "no-cover-article",
        body: ~s(<p>Body without cover image.</p>),
        cover_image_url: nil,
        published: true,
        publishing_date: @past_publication
      )

    conn = get(conn, ~p"/blog/#{article.slug}")
    html = html_response(conn, 200)

    refute html =~ ~s(id="blog-article-cover")
  end

  test "GET /blog uses the first CDN body image as card fallback when no cover is set", %{
    conn: conn
  } do
    previous_endpoint = Application.get_env(:voria2, :storage_public_endpoint)
    Application.put_env(:voria2, :storage_public_endpoint, "https://media.test")
    on_exit(fn -> Application.put_env(:voria2, :storage_public_endpoint, previous_endpoint) end)

    create_blog_article(
      title: "Fallback Article",
      slug: "fallback-article",
      body:
        ~s(<p>Intro</p><img src="https://media.test/blogcontent/files/cover.webp" alt="cover"><img src="https://media.test/blogcontent/files/second.webp" alt="second">),
      cover_image_url: nil,
      published: true,
      publishing_date: @past_publication
    )

    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)

    assert html =~ ~s(src="https://media.test/blogcontent/files/cover.webp")
    refute html =~ ~s(hero-newspaper)
  end

  test "GET /blog ignores non-CDN body images when no cover is set", %{conn: conn} do
    previous_endpoint = Application.get_env(:voria2, :storage_public_endpoint)
    Application.put_env(:voria2, :storage_public_endpoint, "https://media.test")
    on_exit(fn -> Application.put_env(:voria2, :storage_public_endpoint, previous_endpoint) end)

    create_blog_article(
      title: "External Image Article",
      slug: "external-image-article",
      body: ~s(<p>Intro</p><img src="https://external.example.com/image.jpg" alt="external">),
      cover_image_url: nil,
      published: true,
      publishing_date: @past_publication
    )

    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)

    refute html =~ ~s(src="https://external.example.com/image.jpg")
    assert html =~ ~s(hero-newspaper)
  end

  test "GET /blog/:slug returns 404 for draft articles to anonymous users", %{conn: conn} do
    article = create_blog_article(title: "Draft Article", slug: "draft-article", published: false)

    conn = get(conn, ~p"/blog/#{article.slug}")

    assert response(conn, 404) == "Not found"
  end

  test "GET /blog hides scheduled articles from anonymous users", %{conn: conn} do
    article =
      create_blog_article(
        title: "Scheduled Article",
        slug: "scheduled-article",
        published: true,
        publishing_date: @future_publication
      )

    conn = get(conn, ~p"/blog/#{article.slug}")

    assert response(conn, 404) == "Not found"
  end

  test "GET /blog/:slug lets admins preview drafts", %{conn: conn} do
    admin = create_admin()
    article = create_blog_article(title: "Draft Article", slug: "draft-article", published: false)

    conn =
      conn
      |> log_in(admin)
      |> get(~p"/blog/#{article.slug}")

    html = html_response(conn, 200)

    assert html =~ "Draft Article"
    assert html =~ "id=\"blog-draft-preview\""
  end

  test "GET /blog/:slug lets admins preview scheduled articles", %{conn: conn} do
    admin = create_admin()

    article =
      create_blog_article(
        title: "Scheduled Article",
        slug: "scheduled-article",
        published: true,
        publishing_date: @future_publication
      )

    conn =
      conn
      |> log_in(admin)
      |> get(~p"/blog/#{article.slug}")

    html = html_response(conn, 200)

    assert html =~ "Scheduled Article"
    assert html =~ "id=\"blog-scheduled-preview\""
  end

  test "GET /blog orders articles by publishing date descending", %{conn: conn} do
    older =
      create_blog_article(
        title: "Older Article",
        slug: "older-article",
        published: true,
        publishing_date: ~U[2026-05-01 09:00:00Z]
      )

    newer =
      create_blog_article(
        title: "Newer Article",
        slug: "newer-article",
        published: true,
        publishing_date: ~U[2026-05-03 09:00:00Z]
      )

    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)

    assert title_position(html, newer.title) < title_position(html, older.title)
  end

  test "GET /blog/:slug uses publishing date in article metadata", %{conn: conn} do
    article =
      create_blog_article(
        title: "Metadata Article",
        slug: "metadata-article",
        published: true,
        publishing_date: @past_publication
      )

    conn = get(conn, ~p"/blog/#{article.slug}")
    html = html_response(conn, 200)

    assert html =~ ~s(property="article:published_time")
    assert html =~ DateTime.to_iso8601(article.publishing_date)
    refute html =~ ~s(property="article:modified_time")
    refute html =~ DateTime.to_iso8601(article.updated_at)
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end
end
