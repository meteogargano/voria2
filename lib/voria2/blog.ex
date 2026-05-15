defmodule Voria2.Blog do
  use Ash.Domain, otp_app: :voria2

  require Ash.Query

  resources do
    resource Voria2.Blog.Article do
      define :create_article, action: :create
      define :list_articles, action: :read
      define :get_article, action: :read, get_by: [:id]
      define :get_article_by_slug, action: :read, get_by: [:slug]
      define :update_article, action: :update
      define :destroy_article, action: :destroy
    end

    resource Voria2.Blog.Category do
      define :create_category, action: :create
      define :list_categories, action: :read
      define :get_category, action: :read, get_by: [:id]
      define :find_category_by_name, action: :by_name, args: [:name]
      define :destroy_category, action: :destroy
    end

    resource Voria2.Blog.ArticleCategory
  end

  def list_published_articles(filters \\ %{}, opts \\ [])
      when is_map(filters) or is_list(filters) do
    filters = Enum.into(filters, %{})

    Voria2.Blog.Article
    |> Ash.Query.filter(published == true)
    |> maybe_filter_article_title(Map.get(filters, :q) || Map.get(filters, "q"))
    |> maybe_filter_article_category(Map.get(filters, :category) || Map.get(filters, "category"))
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.read(opts)
  end

  def get_public_article_by_slug(slug, opts \\ []) when is_binary(slug) do
    if admin_actor?(Keyword.get(opts, :actor)) do
      get_article_by_slug(slug, opts)
    else
      Voria2.Blog.Article
      |> Ash.Query.filter(slug == ^slug and published == true)
      |> Ash.read_one(opts)
      |> case do
        {:ok, nil} -> {:error, :not_found}
        other -> other
      end
    end
  end

  def list_published_categories(opts \\ []) do
    case list_published_articles(%{}, Keyword.put_new(opts, :load, categories: [:name])) do
      {:ok, articles} ->
        {:ok,
         articles
         |> Enum.flat_map(& &1.categories)
         |> Enum.uniq_by(& &1.id)
         |> Enum.sort_by(&sort_category_name/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_categories(query, opts \\ []) when is_binary(query) do
    trimmed_query = String.trim(query)

    category_query =
      if trimmed_query == "" do
        Voria2.Blog.Category
      else
        pattern = "%#{String.downcase(trimmed_query)}%"

        Voria2.Blog.Category
        |> Ash.Query.filter(fragment("lower(?) like ?", name, ^pattern))
      end

    category_query
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(12)
    |> Ash.read(opts)
  end

  defp maybe_filter_article_title(query, title_query) when is_binary(title_query) do
    trimmed_query = String.trim(title_query)

    if trimmed_query == "" do
      query
    else
      pattern = "%#{String.downcase(trimmed_query)}%"
      Ash.Query.filter(query, fragment("lower(?) like ?", title, ^pattern))
    end
  end

  defp maybe_filter_article_title(query, _title_query), do: query

  defp maybe_filter_article_category(query, category) when is_binary(category) do
    trimmed_category = String.trim(category)

    if trimmed_category == "" do
      query
    else
      Ash.Query.filter(query, categories.name == ^trimmed_category)
    end
  end

  defp maybe_filter_article_category(query, _category), do: query

  defp admin_actor?(%{admin: true}), do: true
  defp admin_actor?(_actor), do: false

  defp sort_category_name(category), do: String.downcase(to_string(category.name))
end
