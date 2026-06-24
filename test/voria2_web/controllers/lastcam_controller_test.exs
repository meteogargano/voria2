defmodule Voria2Web.LastcamControllerTest do
  use Voria2Web.ConnCase, async: false

  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()
    installation = create_installation(user)
    %{user: user, installation: installation}
  end

  describe "GET /lastcam" do
    test "lists active webcams with links", %{conn: conn, installation: installation} do
      _cam_a = create_webcam(installation, name: "Cam A", slug: "cam-a")
      _cam_b = create_webcam(installation, name: "Cam B", slug: "cam-b")
      inactive = create_webcam(installation, name: "Cam C", slug: "cam-c")
      {:ok, _} = Voria2.Network.update_webcam(inactive, %{is_active: false}, authorize?: false)

      conn = get(conn, "/lastcam")

      assert html_response(conn, 200) =~ "Lastcam"
      assert conn.resp_body =~ "/lastcam/cam-a"
      assert conn.resp_body =~ "/lastcam/cam-b"
      assert conn.resp_body =~ "Cam A"
      assert conn.resp_body =~ "Cam B"
      refute conn.resp_body =~ "/lastcam/cam-c"
      refute conn.resp_body =~ "Cam C"
    end

    test "shows empty list when no webcams exist", %{conn: conn} do
      conn = get(conn, "/lastcam")

      assert html_response(conn, 200) =~ "Lastcam"
    end
  end

  describe "GET /lastcam/:slug" do
    test "returns latest shot bytes as image/webp", %{conn: conn, installation: installation} do
      webcam = create_webcam(installation, name: "Test Cam", slug: "test-cam")
      s3_key = "webcams/#{webcam.id}/shot.webp"
      image_bytes = "fake-webp-bytes"

      :ok = Voria2.Storage.Stub.put_object(s3_key, image_bytes, bucket: "voria2-media")

      {:ok, _shot} =
        Voria2.Network.record_webcam_shot(
          %{
            webcam_id: webcam.id,
            captured_at: DateTime.utc_now(),
            s3_key: s3_key,
            s3_bucket: "voria2-media",
            original_hash: "hash-#{webcam.id}-1",
            width: 1280,
            height: 720,
            file_size_bytes: byte_size(image_bytes)
          },
          authorize?: false
        )

      Voria2.Cache.invalidate_latest_shot(webcam.id)

      conn = get(conn, "/lastcam/test-cam")

      assert response(conn, 200) == image_bytes
      assert get_resp_header(conn, "content-type") == ["image/webp"]
    end

    test "returns most recent shot when multiple exist", %{
      conn: conn,
      installation: installation
    } do
      webcam = create_webcam(installation, name: "Multi Cam", slug: "multi-cam")
      old_key = "webcams/#{webcam.id}/old.webp"
      new_key = "webcams/#{webcam.id}/new.webp"

      :ok = Voria2.Storage.Stub.put_object(old_key, "old-bytes", bucket: "voria2-media")
      :ok = Voria2.Storage.Stub.put_object(new_key, "new-bytes", bucket: "voria2-media")

      base = DateTime.utc_now()

      {:ok, _} =
        Voria2.Network.record_webcam_shot(
          %{
            webcam_id: webcam.id,
            captured_at: DateTime.add(base, -120, :second),
            s3_key: old_key,
            s3_bucket: "voria2-media",
            original_hash: "hash-#{webcam.id}-old",
            width: 100,
            height: 100,
            file_size_bytes: 9
          },
          authorize?: false
        )

      {:ok, _} =
        Voria2.Network.record_webcam_shot(
          %{
            webcam_id: webcam.id,
            captured_at: base,
            s3_key: new_key,
            s3_bucket: "voria2-media",
            original_hash: "hash-#{webcam.id}-new",
            width: 100,
            height: 100,
            file_size_bytes: 9
          },
          authorize?: false
        )

      Voria2.Cache.invalidate_latest_shot(webcam.id)

      conn = get(conn, "/lastcam/multi-cam")

      assert response(conn, 200) == "new-bytes"
    end

    test "returns 404 for unknown slug", %{conn: conn} do
      conn = get(conn, "/lastcam/missing-cam")

      assert response(conn, 404) == "Not found"
    end

    test "returns 404 when webcam has no shots", %{conn: conn, installation: installation} do
      webcam = create_webcam(installation, name: "Empty Cam", slug: "empty-cam")

      Voria2.Cache.invalidate_latest_shot(webcam.id)

      conn = get(conn, "/lastcam/empty-cam")

      assert response(conn, 404) == "Not found"
    end
  end
end
