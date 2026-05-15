defmodule Voria2Web.BlogContentControllerTest do
  use Voria2Web.ConnCase, async: false

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Voria2.MeasurementsHelpers

  setup %{conn: conn} do
    Voria2.Storage.Stub.reset!()

    admin = create_admin()
    user = create_user()

    Voria2.Storage.Stub.put_object("blogcontent/readme.txt", "hello from r2",
      content_type: "text/plain",
      last_modified: "2026-05-01T10:00:00Z"
    )

    on_exit(fn ->
      Voria2.Storage.Stub.reset!()
    end)

    %{conn: conn, admin: admin, user: user}
  end

  test "admin can fetch inline preview", %{conn: conn, admin: admin} do
    conn = conn |> log_in(admin) |> get(~p"/manage/blogcontent/files/readme.txt")

    assert response(conn, 200) == "hello from r2"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(conn, "content-disposition") == ["inline"]
  end

  test "admin can request attachment download", %{conn: conn, admin: admin} do
    conn = conn |> log_in(admin) |> get(~p"/manage/blogcontent/files/readme.txt?download=1")

    assert response(conn, 200) == "hello from r2"
    assert get_resp_header(conn, "content-disposition") == ["attachment"]
  end

  test "non-admin users are redirected", %{conn: conn, user: user} do
    conn = conn |> log_in(user) |> get(~p"/manage/blogcontent/files/readme.txt")

    assert redirected_to(conn) == ~p"/manage"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) in [
             "Admin access required.",
             "Accesso admin richiesto."
           ]
  end

  test "returns 404 for missing files", %{conn: conn, admin: admin} do
    conn = conn |> log_in(admin) |> get(~p"/manage/blogcontent/files/missing.txt")

    assert response(conn, 404) == "Not found"
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end
end
