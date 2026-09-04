defmodule Voria2Web.PageController do
  use Voria2Web, :controller

  def home(conn, _params) do
    {:ok, latest_articles} =
      Voria2.Blog.list_published_articles(%{},
        actor: conn.assigns[:current_user],
        load: [categories: [:name]]
      )

    latest_shot = latest_homepage_shot()

    render(conn, :home,
      latest_articles: Enum.take(latest_articles, 3),
      latest_shot: latest_shot,
      page_meta: %{
        title: "Homepage",
        description:
          "Rete meteo, webcam e contenuti editoriali per seguire in tempo reale il Gargano, leggere i microclimi locali e consultare un archivio costruito nel tempo.",
        type: "website",
        url: current_url(conn, %{})
      },
      page_title: gettext("Homepage")
    )
  end

  def associazione(conn, _params) do
    render(conn, :associazione,
      page_meta: %{
        title: "Associazione MeteoGargano",
        description:
          "Scopri la storia, le finalita' e il lavoro dell'associazione MeteoGargano, nata per osservare e raccontare in modo continuativo il territorio del Gargano.",
        type: "website",
        url: current_url(conn, %{})
      },
      page_title: gettext("Associazione")
    )
  end

  def statuto(conn, _params) do
    render(conn, :statuto, page_title: gettext("Statuto"))
  end

  defp latest_homepage_shot do
    Voria2.Network.WebcamShot
    |> Ash.Query.sort(captured_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load(:webcam)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> nil
      {:ok, shot} -> shot
      {:error, _reason} -> nil
    end
  end
end
