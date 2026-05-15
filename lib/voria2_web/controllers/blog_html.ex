defmodule Voria2Web.BlogHTML do
  use Voria2Web, :html

  embed_templates "blog_html/*"

  @excerpt_length 200
  @html_entities %{
    "amp" => "&",
    "apos" => "'",
    "copy" => "©",
    "gt" => ">",
    "hellip" => "…",
    "laquo" => "«",
    "ldquo" => "\"",
    "lsaquo" => "‹",
    "lsquo" => "'",
    "lt" => "<",
    "mdash" => "—",
    "nbsp" => " ",
    "ndash" => "–",
    "quot" => "\"",
    "raquo" => "»",
    "reg" => "®",
    "rdquo" => "\"",
    "rsaquo" => "›",
    "rsquo" => "'",
    "trade" => "™"
  }

  def article_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%B %-d, %Y")

  def article_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def excerpt(body) when is_binary(body) do
    body
    |> strip_html()
    |> decode_html_entities()
    |> strip_html()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> truncate(@excerpt_length)
  end

  def excerpt(_body), do: ""

  def blog_path(params \\ %{}) do
    params =
      params
      |> Enum.into(%{})
      |> Enum.reject(fn {_key, value} -> blank?(value) end)
      |> Map.new()

    ~p"/blog?#{params}"
  end

  def cover_image?(url) when is_binary(url), do: String.trim(url) != ""
  def cover_image?(_url), do: false

  def category_options(categories) do
    [
      {gettext("All categories"), ""}
      | Enum.map(categories, &{to_string(&1.name), to_string(&1.name)})
    ]
  end

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - 1) <> "…"
    end
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<!--.*?-->/us, " ")
    |> String.replace(~r/<(?:script|style)\b[^>]*>.*?<\/(?:script|style)>/uis, " ")
    |> String.replace(~r/<![^>]*>/u, " ")
    |> String.replace(~r/<\/?[a-zA-Z][^>]*>/u, " ")
  end

  defp decode_html_entities(text) do
    text
    |> decode_entities_once()
    |> decode_entities_once()
  end

  defp decode_entities_once(text) do
    text
    |> then(fn value ->
      Regex.replace(~r/&#(\d+);/u, value, fn _, digits ->
        digits
        |> String.to_integer()
        |> codepoint_or_space()
      end)
    end)
    |> then(fn value ->
      Regex.replace(~r/&#x([0-9a-fA-F]+);/u, value, fn _, digits ->
        digits
        |> String.to_integer(16)
        |> codepoint_or_space()
      end)
    end)
    |> then(fn value ->
      Regex.replace(~r/&([a-zA-Z][a-zA-Z0-9]+);/u, value, fn _, name ->
        Map.get(@html_entities, String.downcase(name), " ")
      end)
    end)
  end

  defp codepoint_or_space(codepoint) when codepoint in 0xD800..0xDFFF, do: " "

  defp codepoint_or_space(codepoint) when codepoint >= 0 and codepoint <= 0x10FFFF,
    do: <<codepoint::utf8>>

  defp codepoint_or_space(_codepoint), do: " "

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
