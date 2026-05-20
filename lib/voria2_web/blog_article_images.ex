defmodule Voria2Web.BlogArticleImages do
  @moduledoc false

  @image_extensions [".avif", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp"]
  @image_src_pattern ~r/<img\b[^>]*\bsrc\s*=\s*(['"])([^'"]+)\1/iu

  def article_card_image_url(article) when is_map(article) do
    normalized_cover_image_url(Map.get(article, :cover_image_url)) ||
      first_cdn_body_image_url(Map.get(article, :body))
  end

  def article_card_image_url(_article), do: nil

  def normalized_cover_image_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      normalized_url -> normalized_url
    end
  end

  def normalized_cover_image_url(_url), do: nil

  def first_cdn_body_image_url(body) when is_binary(body) do
    case storage_public_prefix() do
      nil -> nil
      prefix -> first_matching_cdn_image(body, prefix)
    end
  end

  def first_cdn_body_image_url(_body), do: nil

  defp first_matching_cdn_image(body, prefix) do
    body
    |> then(&Regex.scan(@image_src_pattern, &1, capture: :all_but_first))
    |> Enum.find_value(fn [_quote, url] ->
      normalized_url = String.trim(url)

      if String.starts_with?(normalized_url, prefix) and image_url?(normalized_url) do
        normalized_url
      end
    end)
  end

  defp storage_public_prefix do
    case Application.get_env(:voria2, :storage_public_endpoint) do
      endpoint when is_binary(endpoint) ->
        case String.trim(endpoint) do
          "" -> nil
          normalized_endpoint -> String.trim_trailing(normalized_endpoint, "/") <> "/"
        end

      _endpoint ->
        nil
    end
  end

  defp image_url?(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> case do
      path when is_binary(path) -> String.downcase(Path.extname(path)) in @image_extensions
      _path -> false
    end
  end
end
