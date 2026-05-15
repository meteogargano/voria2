defmodule Voria2Web.HealthControllerTest do
  use Voria2Web.ConnCase, async: true

  test "GET /healthz", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
