defmodule Voria2Web.LastcamController do
  use Voria2Web, :controller

  require Ash.Query

  def index(conn, _params) do
    webcams =
      Voria2.Network.Webcam
      |> Ash.Query.filter(is_active == true)
      |> Ash.Query.sort(name: :asc, slug: :asc)
      |> Ash.read!(authorize?: false)

    body =
      [
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>Lastcam</title></head><body>",
        "<h1>Lastcam</h1><ul>",
        Enum.map(webcams, fn webcam ->
          name = webcam.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          slug = webcam.slug |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

          ["<li><a href=\"", ~p"/lastcam/#{webcam.slug}", "\">", name, " (", slug, ")</a></li>"]
        end),
        "</ul></body></html>"
      ]
      |> IO.iodata_to_binary()

    html(conn, body)
  end

  def show(conn, %{"slug" => slug}) do
    with {:ok, webcam} <- Voria2.Network.get_webcam_by_slug(slug, authorize?: false),
         {:ok, %{body: body, content_type: content_type}} <-
           Voria2.Cache.latest_shot_bytes_for_webcam(webcam.id) do
      conn
      |> put_resp_content_type(content_type || "image/webp", nil)
      |> send_resp(200, body)
    else
      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
