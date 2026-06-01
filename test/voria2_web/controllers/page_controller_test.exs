defmodule Voria2Web.PageControllerTest do
  use Voria2Web.ConnCase

  import Voria2.MeasurementsHelpers

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "MeteoGargano"
    assert html =~ ~p"/blog"
  end

  test "GET / uses the first CDN body image as homepage card fallback", %{conn: conn} do
    previous_endpoint = Application.get_env(:voria2, :storage_public_endpoint)
    Application.put_env(:voria2, :storage_public_endpoint, "https://media.test")
    on_exit(fn -> Application.put_env(:voria2, :storage_public_endpoint, previous_endpoint) end)

    create_blog_article(
      title: "Homepage Fallback Article",
      slug: "homepage-fallback-article",
      body:
        ~s(<p>Intro</p><img src="https://media.test/blogcontent/files/home-cover.webp" alt="cover">),
      cover_image_url: nil,
      published: true,
      publishing_date: ~U[2026-05-01 10:00:00Z]
    )

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(src="https://media.test/blogcontent/files/home-cover.webp")
  end

  test "GET / renders latest webcam timestamp for local browser formatting", %{conn: conn} do
    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)

    {:ok, shot} =
      Voria2.Network.record_webcam_shot(
        %{
          webcam_id: webcam.id,
          captured_at: ~U[2026-05-01 10:15:00Z],
          s3_key: "webcams/#{webcam.id}/latest.webp",
          s3_bucket: "voria2-media",
          original_hash: "hash-latest-shot",
          width: 1280,
          height: 720,
          file_size_bytes: 1024
        },
        authorize?: false
      )

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(id="homepage-latest-shot-timestamp")
    assert html =~ ~s(data-local-time="true")
    assert html =~ ~s(data-ts="#{DateTime.to_unix(shot.captured_at, :millisecond)}")
    assert html =~ ~s(datetime="2026-05-01T10:15:00Z")
  end
end
