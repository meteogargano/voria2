defmodule Voria2Web.PageControllerTest do
  use Voria2Web.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "MeteoGargano"
    assert html =~ ~p"/blog"
  end
end
