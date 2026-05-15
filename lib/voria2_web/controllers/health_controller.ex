defmodule Voria2Web.HealthController do
  use Voria2Web, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
