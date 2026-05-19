defmodule Voria2Web.ManageBlogContentLiveTest do
  use Voria2Web.ConnCase, async: false

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup %{conn: conn} do
    Voria2.Storage.Stub.reset!()

    admin = create_admin()
    user = create_user()

    conn = log_in(conn, admin)

    on_exit(fn ->
      Voria2.Storage.Stub.reset!()
    end)

    %{conn: conn, admin: admin, user: user}
  end

  test "non-admin users are redirected away from the page", %{user: user} do
    conn = Phoenix.ConnTest.build_conn() |> log_in(user)

    assert {:error, {:live_redirect, %{to: "/manage", flash: flash}}} =
             live(conn, ~p"/manage/blogcontent")

    assert flash["error"] in ["Admin access required.", "Accesso admin richiesto."]
  end

  test "lists existing files and previews selected items", %{conn: conn} do
    Voria2.Storage.Stub.put_object("blogcontent/welcome.txt", "hello world",
      content_type: "text/plain",
      last_modified: "2026-05-01T10:00:00Z"
    )

    Voria2.Storage.Stub.put_object("blogcontent/cover.jpg", "jpeg-bytes",
      content_type: "image/jpeg",
      last_modified: "2026-05-02T12:00:00Z"
    )

    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    assert has_element?(view, "#blogcontent-file-blogcontent-welcome-txt", "welcome.txt")
    assert has_element?(view, "#blogcontent-file-blogcontent-cover-jpg", "cover.jpg")
    assert has_element?(view, "#blogcontent-preview-empty")

    view
    |> element("#preview-file-blogcontent-welcome-txt")
    |> render_click()

    assert has_element?(view, "#blogcontent-preview", "welcome.txt")
    assert has_element?(view, "#blogcontent-preview-iframe")
  end

  test "uploads and deletes files", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "post.md",
          content: "# Hello",
          type: "text/markdown"
        }
      ])

    upload_html = render_upload(upload, "post.md")

    assert upload_html =~ "File uploaded successfully." or
             upload_html =~ "File caricato con successo."

    assert has_element?(view, "#blogcontent-file-blogcontent-post-md", "post.md")
    assert has_element?(view, "#blogcontent-preview", "post.md")

    render_click(
      element(view, "#delete-file-blogcontent-post-md button[phx-click='delete_file']")
    )

    refute has_element?(view, "#blogcontent-file-blogcontent-post-md")
    assert has_element?(view, "#blogcontent-empty-state")
  end

  test "image uploads keep their original filename when conversion is unchecked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "cover.png",
          content: "png-bytes",
          type: "image/png"
        }
      ])

    render_upload(upload, "cover.png")

    assert has_element?(view, "#blogcontent-file-blogcontent-cover-png", "cover.png")
    refute has_element?(view, "#blogcontent-file-blogcontent-cover-webp")
  end

  test "image uploads are converted to webp when the option is enabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    view
    |> element("#blogcontent-upload-form")
    |> render_change(%{"convert_images_to_webp" => "true"})

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "cover.png",
          content: tiny_png(),
          type: "image/png"
        }
      ])

    render_upload(upload, "cover.png")

    assert has_element?(view, "#blogcontent-file-blogcontent-cover-webp", "cover.webp")
    assert has_element?(view, "#blogcontent-preview", "cover.webp")
    refute has_element?(view, "#blogcontent-file-blogcontent-cover-png")
  end

  test "non-image uploads are not converted when the option is enabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    view
    |> element("#blogcontent-upload-form")
    |> render_change(%{"convert_images_to_webp" => "true"})

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "post.md",
          content: "# Hello",
          type: "text/markdown"
        }
      ])

    render_upload(upload, "post.md")

    assert has_element?(view, "#blogcontent-file-blogcontent-post-md", "post.md")
    refute has_element?(view, "#blogcontent-file-blogcontent-post-webp")
  end

  test "duplicate uploads are auto-renamed", %{conn: conn} do
    Voria2.Storage.Stub.put_object("blogcontent/post.md", "old post",
      content_type: "text/markdown",
      last_modified: "2026-05-01T10:00:00Z"
    )

    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "post.md",
          content: "# New",
          type: "text/markdown"
        }
      ])

    render_upload(upload, "post.md")

    assert has_element?(view, "#blogcontent-file-blogcontent-post-md", "post.md")
    assert has_element?(view, "#blogcontent-file-blogcontent-post-2-md", "post-2.md")
    assert has_element?(view, "#blogcontent-preview", "post-2.md")
  end

  test "converted uploads are auto-renamed against existing webp files", %{conn: conn} do
    Voria2.Storage.Stub.put_object("blogcontent/cover.webp", "old cover",
      content_type: "image/webp",
      last_modified: "2026-05-01T10:00:00Z"
    )

    {:ok, view, _html} = live(conn, ~p"/manage/blogcontent")

    view
    |> element("#blogcontent-upload-form")
    |> render_change(%{"convert_images_to_webp" => "true"})

    upload =
      file_input(view, "#blogcontent-upload-form", :files, [
        %{
          name: "cover.png",
          content: tiny_png(),
          type: "image/png"
        }
      ])

    render_upload(upload, "cover.png")

    assert has_element?(view, "#blogcontent-file-blogcontent-cover-webp", "cover.webp")
    assert has_element?(view, "#blogcontent-file-blogcontent-cover-2-webp", "cover-2.webp")
    assert has_element?(view, "#blogcontent-preview", "cover-2.webp")
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end

  defp tiny_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nX6QAAAAASUVORK5CYII="
    )
  end
end
