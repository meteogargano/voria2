defmodule Voria2Web.BlogControllerTest do
  use Voria2Web.ConnCase, async: true

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Voria2.MeasurementsHelpers

  test "GET /blog lists only published articles and includes navbar link", %{conn: conn} do
    published =
      create_blog_article(
        title: "Storm Update",
        slug: "storm-update",
        body: "<p>Published body</p>",
        published: true
      )

    create_blog_article(title: "Draft Article", slug: "draft-article", published: false)

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
      published: true
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
    create_blog_article(title: "Storm Update", slug: "storm-update", published: true)
    create_blog_article(title: "Rain Report", slug: "rain-report", published: true)

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
      category_ids: [weather.id]
    )

    create_blog_article(
      title: "Climate Brief",
      slug: "climate-brief",
      published: true,
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
        category_ids: [category.id]
      )

    conn = get(conn, ~p"/blog/#{article.slug}")
    html = html_response(conn, 200)

    assert html =~ article.title
    assert html =~ "Wind is increasing."
    assert html =~ article.cover_image_url
    assert html =~ "Weather"
    refute html =~ "Draft preview"
  end

  test "GET /blog/:slug returns 404 for draft articles to anonymous users", %{conn: conn} do
    article = create_blog_article(title: "Draft Article", slug: "draft-article", published: false)

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

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end
end
