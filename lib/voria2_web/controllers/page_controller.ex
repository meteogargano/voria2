defmodule Voria2Web.PageController do
  use Voria2Web, :controller

  require Ash.Query

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
      page_title: gettext("Homepage")
    )
  end

  def associazione(conn, _params) do
    render(conn, :associazione, page_title: gettext("Associazione"))
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
