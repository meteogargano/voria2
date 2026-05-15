defmodule Voria2Web.DailyLogController do
  use Voria2Web, :controller

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
