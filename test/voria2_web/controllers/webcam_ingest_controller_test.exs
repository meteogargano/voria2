defmodule Voria2Web.WebcamIngestControllerTest do
  use Voria2Web.ConnCase, async: false

  import Voria2.MeasurementsHelpers

  @fixture_path Path.expand("../../fixtures/test.jpg", __DIR__)

  setup do
    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)
    api_key = generate_webcam_api_key(webcam, user)

    # Also create a station api key for cross-type auth tests
    station = create_station(installation)
    {:ok, station_key} = Voria2.Network.generate_station_api_key(station.id, actor: user)

    %{
      user: user,
      webcam: webcam,
      api_key: api_key.key,
      station_key: station_key.key
    }
  end

  defp auth(conn, key), do: put_req_header(conn, "x-api-key", key)

  defp upload_conn(conn, key, path \\ nil) do
    image_path = path || @fixture_path

    upload = %Plug.Upload{
      content_type: "image/jpeg",
      filename: Path.basename(image_path),
      path: image_path
    }

    conn
    |> auth(key)
    |> post("/api/v1/webcam/ingest", %{"image" => upload})
  end

  defp temp_file(content) do
    path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}.jpg")
    File.write!(path, content)
    path
  end

  # ── Verify endpoint ──────────────────────────────────────────────────────────

  describe "verify" do
    test "X-Api-Key returns webcam info", %{conn: conn, api_key: key, webcam: webcam} do
      conn = auth(conn, key) |> post("/api/v1/webcam/ingest/verify")
      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["webcam_id"] == webcam.id
      assert resp["webcam_name"] == webcam.name
    end

    test "Bearer token returns webcam info", %{conn: conn, api_key: key, webcam: webcam} do
      conn =
        put_req_header(conn, "authorization", "Bearer #{key}")
        |> post("/api/v1/webcam/ingest/verify")

      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["webcam_id"] == webcam.id
      assert resp["webcam_name"] == webcam.name
    end

    test "missing key → 401", %{conn: conn} do
      conn = post(conn, "/api/v1/webcam/ingest/verify")
      assert json_response(conn, 401)["error"] == "missing_api_key"
    end

    test "invalid key → 401", %{conn: conn} do
      conn = auth(conn, "vwk_invalid") |> post("/api/v1/webcam/ingest/verify")
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end
  end

  # ── Auth tests ──────────────────────────────────────────────────────────────

  describe "auth" do
    test "missing X-Api-Key → 401 missing_api_key", %{conn: conn} do
      conn = post(conn, "/api/v1/webcam/ingest")
      assert json_response(conn, 401)["error"] == "missing_api_key"
    end

    test "invalid key → 401 invalid_api_key", %{conn: conn} do
      conn = auth(conn, "vwk_invalid") |> post("/api/v1/webcam/ingest")
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end

    test "station key (vsk_) on webcam endpoint → 401", %{conn: conn, station_key: key} do
      conn = auth(conn, key) |> post("/api/v1/webcam/ingest")
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end

    test "Bearer token with valid webcam key → passes auth", %{conn: conn, api_key: key} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{key}")
        |> post("/api/v1/webcam/ingest")

      # No api key error — we expect 422 (missing image) not 401
      assert json_response(conn, 422)["error"] == "missing image upload"
    end
  end

  # ── Upload tests ─────────────────────────────────────────────────────────────

  describe "upload" do
    test "valid image under limit → 201 with shot_id and s3_key", %{conn: conn, api_key: key} do
      conn = upload_conn(conn, key)
      resp = json_response(conn, 201)
      assert resp["ok"] == true
      assert is_binary(resp["shot_id"])
      assert is_binary(resp["s3_key"])
      assert String.starts_with?(resp["s3_key"], "webcams/")
      assert String.ends_with?(resp["s3_key"], ".webp")
    end

    test "shot is persisted in DB", %{conn: conn, api_key: key, webcam: webcam} do
      upload_conn(conn, key)

      {:ok, [shot | _]} = Voria2.Network.latest_webcam_shot(webcam.id, authorize?: false)
      assert shot.webcam_id == webcam.id
      assert String.ends_with?(shot.s3_key, ".webp")
    end

    test "missing image param → 422", %{conn: conn, api_key: key} do
      conn = auth(conn, key) |> post("/api/v1/webcam/ingest", %{})
      assert json_response(conn, 422)["error"] == "missing image upload"
    end

    test "invalid binary (non-image) → 422", %{conn: conn, api_key: key} do
      path = temp_file("not an image")
      conn = upload_conn(conn, key, path)
      assert json_response(conn, 422)["ok"] == false
    end

    test "file exceeds size limit → 422", %{conn: conn, api_key: key} do
      # Set a tiny limit for this test
      original = Application.get_env(:voria2, :max_webcam_upload_bytes)
      Application.put_env(:voria2, :max_webcam_upload_bytes, 1)

      conn = upload_conn(conn, key)
      assert json_response(conn, 422)["error"] =~ "exceeds maximum"

      Application.put_env(:voria2, :max_webcam_upload_bytes, original)
    end
  end

  # ── Deduplication tests ───────────────────────────────────────────────────────

  describe "deduplication" do
    test "uploading same binary twice: first 201, second 200 with same shot_id", %{
      conn: conn,
      api_key: key
    } do
      first = upload_conn(conn, key)
      resp1 = json_response(first, 201)
      assert resp1["ok"] == true
      shot_id = resp1["shot_id"]

      second = upload_conn(build_conn(), key)
      resp2 = json_response(second, 200)
      assert resp2["ok"] == true
      assert resp2["duplicate"] == true
      assert resp2["shot_id"] == shot_id
    end
  end

  # ── Cache tests ───────────────────────────────────────────────────────────────

  describe "cache" do
    test "after upload, latest_shot_for_webcam returns new shot", %{
      conn: conn,
      api_key: key,
      webcam: webcam
    } do
      upload_conn(conn, key)

      # Allow PubSub + ETS invalidation to propagate
      Process.sleep(50)

      {:ok, shot} = Voria2.Cache.latest_shot_for_webcam(webcam.id)
      assert shot != nil
      assert shot.webcam_id == webcam.id
    end

    test "all_webcams_latest_shots includes the updated shot", %{
      conn: conn,
      api_key: key,
      webcam: webcam
    } do
      upload_conn(conn, key)
      Process.sleep(50)

      # Invalidate the all-webcams cache so it recomputes fresh
      :ets.delete(:voria2_cache, {:all_webcams_latest})

      {:ok, list} = Voria2.Cache.all_webcams_latest_shots()
      webcam_entry = Enum.find(list, fn %{webcam: w} -> w.id == webcam.id end)
      assert webcam_entry != nil
      assert webcam_entry.latest_shot != nil
    end
  end
end

defmodule Voria2.Network.AdminBulkDeleteTest do
  use Voria2.DataCase, async: false

  import Voria2.MeasurementsHelpers

  @fixture_path Path.expand("../../fixtures/test.jpg", __DIR__)

  setup do
    user = create_user()
    admin = create_admin()
    installation = create_installation(user)
    webcam = create_webcam(installation)

    # Seed a shot record directly
    binary = File.read!(@fixture_path)
    hash = Base.encode16(:crypto.hash(:sha256, binary), case: :lower)

    {:ok, shot} =
      Voria2.Network.record_webcam_shot(
        %{
          webcam_id: webcam.id,
          captured_at: DateTime.utc_now(),
          s3_key: "webcams/#{webcam.id}/test.webp",
          s3_bucket: "voria2-media",
          original_hash: hash,
          width: 1,
          height: 1,
          file_size_bytes: 100
        },
        authorize?: false
      )

    %{user: user, admin: admin, webcam: webcam, shot: shot}
  end

  test "non-admin raises Forbidden", %{user: user, webcam: webcam} do
    from = DateTime.add(DateTime.utc_now(), -60, :second)
    to = DateTime.add(DateTime.utc_now(), 60, :second)

    assert_raise Ash.Error.Forbidden, fn ->
      Voria2.Network.admin_bulk_delete_shots(user, webcam.id, from, to)
    end
  end

  test "admin deletes shots in range → returns {:ok, count}", %{
    admin: admin,
    webcam: webcam,
    shot: shot
  } do
    from = DateTime.add(DateTime.utc_now(), -60, :second)
    to = DateTime.add(DateTime.utc_now(), 60, :second)

    {:ok, count} = Voria2.Network.admin_bulk_delete_shots(admin, webcam.id, from, to)
    assert count == 1

    # Record is gone from DB
    result = Ash.get(Voria2.Network.WebcamShot, shot.id, authorize?: false)
    assert result == {:ok, nil} or match?({:error, _}, result)
  end

  test "admin deletes outside range → returns {:ok, 0}", %{admin: admin, webcam: webcam} do
    # Range entirely in the future
    from = DateTime.add(DateTime.utc_now(), 3600, :second)
    to = DateTime.add(DateTime.utc_now(), 7200, :second)

    {:ok, count} = Voria2.Network.admin_bulk_delete_shots(admin, webcam.id, from, to)
    assert count == 0
  end
end
