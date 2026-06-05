defmodule Voria2Web.DailyLogController do
  use Voria2Web, :controller

  require Ash.Query

  def index(conn, _params) do
    stations =
      Voria2.Network.Station
      |> Ash.Query.filter(is_active == true)
      |> Ash.Query.sort(name: :asc, slug: :asc)
      |> Ash.read!(authorize?: false)

    body =
      [
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>Daily logs</title></head><body>",
        "<h1>Daily logs</h1><ul>",
        Enum.map(stations, fn station ->
          name = station.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          slug = station.slug |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

          ["<li><a href=\"", ~p"/dailylog/#{station.slug}", "\">", name, " (", slug, ")</a></li>"]
        end),
        "</ul></body></html>"
      ]
      |> IO.iodata_to_binary()

    html(conn, body)
  end

  def show(conn, %{"slug" => slug}) do
    with {:ok, station} <- Voria2.Network.get_station_by_slug(slug, authorize?: false),
         {:ok, body} <- Voria2.Cache.get_or_compute_dailylog(station) do
      text(conn, body)
    else
      {:error, _reason} ->
        send_resp(conn, 404, "Not found")
    end
  end
end
