defmodule Voria2Web.BlogController do
  use Voria2Web, :controller

  def index(conn, params) do
    filters = normalize_filters(params)
    actor = conn.assigns[:current_user]

    {:ok, articles} =
      Voria2.Blog.list_published_articles(filters,
        actor: actor,
        load: [categories: [:name]]
      )

    {:ok, categories} = Voria2.Blog.list_published_categories(actor: actor)

    render(conn, :index,
      articles: articles,
      categories: categories,
      current_path: conn.request_path,
      form: Phoenix.Component.to_form(filters, as: nil),
      page_title: gettext("Blog"),
      search_query: filters["q"],
      selected_category: filters["category"]
    )
  end

  def show(conn, %{"slug" => slug}) do
    case Voria2.Blog.get_public_article_by_slug(slug,
           actor: conn.assigns[:current_user],
           load: [categories: [:name]]
         ) do
      {:ok, article} ->
        render(conn, :show,
          article: article,
          current_path: conn.request_path,
          draft_preview?: draft_preview?(article),
          scheduled_preview?: scheduled_preview?(article),
          page_meta: %{
            title: article.title,
            description: Voria2Web.BlogHTML.excerpt(article.body),
            type: "article",
            url: current_url(conn, %{}),
            image: article_meta_image(article),
            image_alt: article.title,
            article_published_time: DateTime.to_iso8601(article.publishing_date),
            article_tags: Enum.map(article.categories, &to_string(&1.name))
          },
          page_title: article.title
        )

      {:error, _reason} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp normalize_filters(params) do
    %{
      "q" => normalize_filter_value(Map.get(params, "q")),
      "category" => normalize_filter_value(Map.get(params, "category"))
    }
  end

  defp normalize_filter_value(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp normalize_filter_value(_value), do: ""

  defp article_meta_image(%{cover_image_url: url}) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      image_url -> image_url
    end
  end

  defp article_meta_image(_article), do: nil

  defp draft_preview?(%{published: false}), do: true
  defp draft_preview?(_article), do: false

  defp scheduled_preview?(%{published: true, publishing_date: %DateTime{} = publishing_date}) do
    DateTime.compare(publishing_date, DateTime.utc_now()) == :gt
  end

  defp scheduled_preview?(_article), do: false
end
