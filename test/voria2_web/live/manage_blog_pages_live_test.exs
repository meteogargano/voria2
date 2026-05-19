defmodule Voria2Web.ManageBlogPagesLiveTest do
  use Voria2Web.ConnCase, async: false

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup %{conn: conn} do
    admin = create_admin()
    user = create_user()

    %{conn: log_in(conn, admin), admin: admin, user: user}
  end

  defp iso(value), do: DateTime.to_iso8601(value)

  test "non-admin users are redirected away from the page", %{user: user} do
    conn = Phoenix.ConnTest.build_conn() |> log_in(user)

    assert {:error, {:live_redirect, %{to: "/manage", flash: flash}}} =
             live(conn, ~p"/manage/blog_pages")

    assert flash["error"] in ["Admin access required.", "Accesso admin richiesto."]
  end

  test "lists existing blog pages", %{conn: conn, admin: admin} do
    weather = create_blog_category(name: "Weather")

    create_blog_article(
      actor: admin,
      title: "Forecast Update",
      slug: "forecast-update",
      published: true,
      publishing_date: ~U[2026-05-01 10:00:00Z],
      category_ids: [weather.id]
    )

    {:ok, view, _html} = live(conn, ~p"/manage/blog_pages")

    assert has_element?(view, "#blog-pages-table", "Forecast Update")
    assert has_element?(view, "#blog-pages-table", "forecast-update")
    assert has_element?(view, "#blog-pages-table", "Weather")
    assert has_element?(view, "#blog-pages-table .badge-success")
  end

  test "creates a blog page and reuses an existing category", %{conn: conn, admin: admin} do
    category = create_blog_category(name: "Weather")
    {:ok, view, _html} = live(conn, ~p"/manage/blog_pages/new")

    render_keyup(element(view, "#blog-page-category-query"), %{"value" => "Wea"})

    assert has_element?(view, "#blog-page-category-option-#{category.id}", "Weather")

    render_click(element(view, "#blog-page-category-option-#{category.id}"))

    assert has_element?(view, "button[phx-click='remove_category']", "Weather")

    view
    |> element("#blog-page-form")
    |> render_submit(%{
      "form" => %{
        "title" => "Spring Outlook",
        "slug" => "spring-outlook",
        "body" => "<p>Strong winds ahead.</p>",
        "cover_image_url" => "https://cdn.example.com/spring.jpg",
        "published" => "true",
        "publishing_date" => iso(~U[2026-05-02 08:30:00Z])
      }
    })

    assert {:ok, article} =
             Voria2.Blog.get_article_by_slug("spring-outlook",
               actor: admin,
               load: [:categories]
             )

    assert article.title == "Spring Outlook"
    assert DateTime.to_unix(article.publishing_date) == DateTime.to_unix(~U[2026-05-02 08:30:00Z])
    assert Enum.map(article.categories, &to_string(&1.name)) == ["Weather"]
  end

  test "creates a new category inline while creating a blog page", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, ~p"/manage/blog_pages/new")

    render_keyup(element(view, "#blog-page-category-query"), %{"value" => "Climate"})

    assert has_element?(view, "#blog-page-create-category")

    render_click(element(view, "#blog-page-create-category"))

    assert has_element?(view, "button[phx-click='remove_category']", "Climate")

    view
    |> element("#blog-page-form")
    |> render_submit(%{
      "form" => %{
        "title" => "Climate Brief",
        "slug" => "climate-brief",
        "body" => "<p>Monthly anomalies.</p>",
        "published" => "false",
        "publishing_date" => iso(~U[2026-05-03 12:45:00Z])
      }
    })

    assert {:ok, article} =
             Voria2.Blog.get_article_by_slug("climate-brief",
               actor: admin,
               load: [:categories]
             )

    assert Enum.map(article.categories, &to_string(&1.name)) == ["Climate"]
    assert DateTime.to_unix(article.publishing_date) == DateTime.to_unix(~U[2026-05-03 12:45:00Z])
  end

  test "edits a blog page and replaces its categories", %{conn: conn, admin: admin} do
    weather = create_blog_category(name: "Weather")
    news = create_blog_category(name: "News")

    article =
      create_blog_article(
        actor: admin,
        title: "Early Draft",
        slug: "early-draft",
        publishing_date: ~U[2026-05-01 09:00:00Z],
        category_ids: [weather.id]
      )

    {:ok, view, _html} = live(conn, ~p"/manage/blog_pages/#{article.id}/edit")

    assert has_element?(view, "button[phx-click='remove_category']", "Weather")

    render_click(
      element(view, "button[phx-click='remove_category'][phx-value-id='#{weather.id}']")
    )

    refute has_element?(view, "button[phx-click='remove_category']", "Weather")

    render_keyup(element(view, "#blog-page-category-query"), %{"value" => "News"})
    render_click(element(view, "#blog-page-category-option-#{news.id}"))

    view
    |> element("#blog-page-form")
    |> render_submit(%{
      "form" => %{
        "title" => "Final Draft",
        "slug" => "final-draft",
        "body" => "<p>Published update.</p>",
        "published" => "true",
        "publishing_date" => iso(~U[2026-05-04 11:15:00Z])
      }
    })

    assert {:ok, updated} = Voria2.Blog.get_article(article.id, actor: admin, load: [:categories])
    assert updated.title == "Final Draft"
    assert updated.slug == "final-draft"
    assert updated.published
    assert DateTime.to_unix(updated.publishing_date) == DateTime.to_unix(~U[2026-05-04 11:15:00Z])
    assert Enum.map(updated.categories, &to_string(&1.name)) == ["News"]
  end

  test "deletes a blog page from the index", %{conn: conn, admin: admin} do
    article = create_blog_article(actor: admin, title: "Delete Me", slug: "delete-me")

    {:ok, view, _html} = live(conn, ~p"/manage/blog_pages")

    render_click(element(view, "#del-blog-page-#{article.id} button[phx-click='delete']"))

    refute has_element?(view, "#blog-pages-table", "Delete Me")
    assert {:error, _} = Voria2.Blog.get_article(article.id)
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end
end
