defmodule Voria2Web.SitemapController do
  use Voria2Web, :controller

  require Ash.Query

  def index(conn, _params) do
    body =
      [
        static_entries(),
        installation_entries(),
        webcam_entries(),
        article_entries()
      ]
      |> List.flatten()
      |> sitemap_xml()

    conn
    |> put_resp_content_type("application/xml", "utf-8")
    |> send_resp(200, body)
  end

  defp static_entries do
    [
      %{loc: url(~p"/")},
      %{loc: url(~p"/associazione")},
      %{loc: url(~p"/blog")},
      %{loc: url(~p"/map")},
      %{loc: url(~p"/compare")},
      %{loc: url(~p"/webcams")}
    ]
  end

  defp installation_entries do
    Voria2.Network.Installation
    |> Ash.Query.filter(is_active == true)
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn installation ->
      %{
        loc: url(~p"/installations/#{installation.id}"),
        lastmod: installation.updated_at
      }
    end)
  end

  defp webcam_entries do
    Voria2.Network.Webcam
    |> Ash.Query.filter(is_active == true)
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn webcam ->
      %{
        loc: url(~p"/webcams/#{webcam.id}/viewer"),
        lastmod: webcam.updated_at
      }
    end)
  end

  defp article_entries do
    {:ok, articles} = Voria2.Blog.list_published_articles(%{}, authorize?: false)

    Enum.map(articles, fn article ->
      %{
        loc: url(~p"/blog/#{article.slug}"),
        lastmod: article.updated_at
      }
    end)
  end

  defp sitemap_xml(entries) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.map(entries, &url_xml/1),
      "</urlset>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp url_xml(%{loc: loc} = entry) do
    [
      "  <url>\n",
      "    <loc>",
      xml_escape(loc),
      "</loc>\n",
      lastmod_xml(entry[:lastmod]),
      "  </url>\n"
    ]
  end

  defp lastmod_xml(nil), do: []

  defp lastmod_xml(lastmod) do
    ["    <lastmod>", xml_escape(lastmod_to_string(lastmod)), "</lastmod>\n"]
  end

  defp lastmod_to_string(%DateTime{} = lastmod), do: DateTime.to_iso8601(lastmod)
  defp lastmod_to_string(%NaiveDateTime{} = lastmod), do: NaiveDateTime.to_iso8601(lastmod)
  defp lastmod_to_string(%Date{} = lastmod), do: Date.to_iso8601(lastmod)

  defp xml_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
