defmodule Voria2Web.IngestControllerTest do
  use Voria2Web.ConnCase, async: false

  require Ash.Query
  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    {:ok, api_key} = Voria2.Network.generate_station_api_key(station.id, actor: user)
    %{user: user, station: station, api_key: api_key.key}
  end

  defp auth(conn, key), do: put_req_header(conn, "x-api-key", key)
  defp auth_bearer(conn, key), do: put_req_header(conn, "authorization", "Bearer #{key}")

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp raw_post(conn, path, body_str) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body_str)
  end

  # ── Auth tests ──────────────────────────────────────────────────────────────

  describe "auth" do
    test "missing X-Api-Key → 401 missing_api_key", %{conn: conn} do
      conn =
        raw_post(conn, "/api/v1/ingest", ~s({"sensor":"t","timestamp":"2026-01-01T00:00:00Z"}))

      assert json_response(conn, 401)["error"] == "missing_api_key"
    end

    test "wrong key value → 401 invalid_api_key", %{conn: conn} do
      conn = auth(conn, "vsk_wrong") |> raw_post("/api/v1/ingest", ~s({}))
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end

    test "empty string key → 401 missing_api_key", %{conn: conn} do
      conn = auth(conn, "") |> raw_post("/api/v1/ingest", ~s({}))
      assert json_response(conn, 401)["error"] == "missing_api_key"
    end

    test "Bearer token with wrong key → 401", %{conn: conn} do
      conn = auth_bearer(conn, "vsk_wrong") |> raw_post("/api/v1/ingest", ~s({}))
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end

    test "Bearer token with empty value → 401", %{conn: conn} do
      conn =
        put_req_header(conn, "authorization", "Bearer ") |> raw_post("/api/v1/ingest", ~s({}))

      assert json_response(conn, 401)["error"] == "missing_api_key"
    end
  end

  # ── Verify endpoint ──────────────────────────────────────────────────────────

  describe "verify" do
    test "X-Api-Key returns station info", %{conn: conn, api_key: key, station: station} do
      conn = auth(conn, key) |> post("/api/v1/ingest/verify")
      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["station_id"] == station.id
      assert resp["station_name"] == station.name
    end

    test "Bearer token returns station info", %{conn: conn, api_key: key, station: station} do
      conn = auth_bearer(conn, key) |> post("/api/v1/ingest/verify")
      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["station_id"] == station.id
      assert resp["station_name"] == station.name
    end

    test "missing key → 401", %{conn: conn} do
      conn = post(conn, "/api/v1/ingest/verify")
      assert json_response(conn, 401)["error"] == "missing_api_key"
    end

    test "invalid key → 401", %{conn: conn} do
      conn = auth(conn, "vsk_invalid") |> post("/api/v1/ingest/verify")
      assert json_response(conn, 401)["error"] == "invalid_api_key"
    end
  end

  # ── Bearer token full pipeline ────────────────────────────────────────────────
  # End-to-end: verify identity → ingest via Bearer → cache lookup → DB persist → summary

  describe "Bearer token full pipeline" do
    setup %{station: station} do
      # The temperature summary helper looks for sensor with mt slug "temperature"
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      Voria2.Cache.invalidate_sensor(station.id, "temperature")
      %{sensor: sensor}
    end

    test "verify → ingest → persist → summary", %{
      conn: conn,
      api_key: key,
      station: station,
      sensor: sensor,
      user: user
    } do
      # 1. Verify station identity via Bearer
      verify = auth_bearer(conn, key) |> post("/api/v1/ingest/verify")
      verify_resp = json_response(verify, 200)
      assert verify_resp["ok"] == true
      assert verify_resp["station_id"] == station.id

      # 2. Ingest a temperature reading via Bearer
      # Place the reading 30 min ago so it falls inside the summary's default 1-hour window
      reading_time = DateTime.add(DateTime.utc_now(), -30 * 60, :second)
      ts = DateTime.to_iso8601(reading_time)

      ingest =
        auth_bearer(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: ts,
          value: 19.7
        })

      assert json_response(ingest, 201)["ok"] == true

      # 3. Confirm reading persisted in DB
      from = DateTime.add(reading_time, -60, :second)
      to = DateTime.add(reading_time, 60, :second)

      readings =
        Voria2.Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)

      assert length(readings) == 1
      assert hd(readings).value == 19.7

      # 4. Confirm summary (recap) reflects the ingested reading.
      # Pass explicit `at` = now so the reading 30 min ago is inside [now-1h, now].
      at = DateTime.utc_now()
      {:ok, summary} = Voria2.Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert summary.current == 19.7
      assert length(summary.history) >= 1
    end
  end

  # ── Temperature tests ────────────────────────────────────────────────────────

  describe "temperature ingest" do
    setup %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      # Invalidate so cache picks up the new sensor
      Voria2.Cache.invalidate_sensor(station.id, "temperature")
      %{sensor: sensor}
    end

    test "valid payload → 201 ok", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2026-03-18T10:30:00Z",
          value: 23.5
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "missing value field → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2026-03-18T10:30:00Z"
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "value is a string → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2026-03-18T10:30:00Z",
          value: "not a number"
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "value is null → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2026-03-18T10:30:00Z",
          value: nil
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "extra unknown fields ignored → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2026-03-18T10:30:00Z",
          value: 21.0,
          extra: "ignored"
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "missing timestamp → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          value: 21.0
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "malformed timestamp → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "not-a-date",
          value: 21.0
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "future timestamp → 201 (allowed)", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2027-01-01T00:00:00Z",
          value: 19.0
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "past timestamp → 201 (allowed)", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "temperature",
          timestamp: "2020-06-15T12:00:00Z",
          value: 25.0
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "reading stored in DB with correct value and timestamp", %{
      conn: conn,
      api_key: key,
      sensor: sensor
    } do
      ts = "2026-03-18T10:30:00Z"
      val = 23.5

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "temperature",
        timestamp: ts,
        value: val
      })

      from = DateTime.from_iso8601("2026-03-18T10:00:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T11:00:00Z") |> elem(1)

      readings =
        Voria2.Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)

      assert length(readings) == 1
      assert hd(readings).value == val
    end
  end

  # ── Wind tests ────────────────────────────────────────────────────────────────

  describe "wind ingest" do
    setup %{station: station} do
      mt = create_measurement_type(slug: "wind", storage_type: :wind)
      sensor = create_sensor_installation(station, mt)
      Voria2.Cache.invalidate_sensor(station.id, "wind")
      %{sensor: sensor}
    end

    test "valid {u: 0, v: -1} → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "wind",
          timestamp: "2026-03-18T10:00:00Z",
          u: 0,
          v: -1
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "valid with gust → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "wind",
          timestamp: "2026-03-18T10:00:00Z",
          u: 3,
          v: -4,
          gust: 5.0
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "missing u → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "wind",
          timestamp: "2026-03-18T10:00:00Z",
          v: -1
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "missing v → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "wind",
          timestamp: "2026-03-18T10:00:00Z",
          u: 3
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "u is string → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "wind",
          timestamp: "2026-03-18T10:00:00Z",
          u: "north",
          v: -1
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "no gust field → 201, gust stored as nil", %{conn: conn, api_key: key, sensor: sensor} do
      ts = "2026-03-18T10:00:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "wind",
        timestamp: ts,
        u: 1,
        v: 0
      })

      from = DateTime.from_iso8601("2026-03-18T09:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T10:10:00Z") |> elem(1)
      readings = Voria2.Measurements.wind_for_sensor!(sensor.id, from, to, authorize?: false)
      assert length(readings) == 1
      assert is_nil(hd(readings).gust)
    end

    test "gust: null → 201, gust stored as nil", %{conn: conn, api_key: key, sensor: sensor} do
      ts = "2026-03-18T10:01:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "wind",
        timestamp: ts,
        u: 1,
        v: 0,
        gust: nil
      })

      from = DateTime.from_iso8601("2026-03-18T09:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T10:10:00Z") |> elem(1)
      readings = Voria2.Measurements.wind_for_sensor!(sensor.id, from, to, authorize?: false)
      assert length(readings) == 1
      assert is_nil(hd(readings).gust)
    end

    test "speed ≈ 5.0 for u=3, v=-4", %{conn: conn, api_key: key, sensor: sensor} do
      ts = "2026-03-18T10:02:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "wind",
        timestamp: ts,
        u: 3,
        v: -4
      })

      from = DateTime.from_iso8601("2026-03-18T09:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T10:10:00Z") |> elem(1)

      readings =
        Voria2.Measurements.WindMeasurement
        |> Ash.Query.filter(
          sensor_installation_id == ^sensor.id and measured_at >= ^from and measured_at <= ^to
        )
        |> Ash.Query.load([:speed])
        |> Ash.read!(authorize?: false)

      assert length(readings) == 1
      assert_in_delta hd(readings).speed, 5.0, 0.001
    end
  end

  # ── Rain tests ────────────────────────────────────────────────────────────────

  describe "rain ingest" do
    setup %{station: station} do
      mt_interval = create_measurement_type(slug: "rain-interval", storage_type: :rain)
      sensor_interval = create_sensor_installation(station, mt_interval, rain_mode: :interval)

      mt_cumulative = create_measurement_type(slug: "rain-cumulative", storage_type: :rain)

      sensor_cumulative =
        create_sensor_installation(station, mt_cumulative, rain_mode: :cumulative)

      Voria2.Cache.invalidate_sensor(station.id, "rain-interval")
      Voria2.Cache.invalidate_sensor(station.id, "rain-cumulative")

      %{sensor_interval: sensor_interval, sensor_cumulative: sensor_cumulative}
    end

    test "valid interval → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-interval",
          timestamp: "2026-03-18T10:00:00Z",
          interval_mm: 2.5
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "valid cumulative → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-cumulative",
          timestamp: "2026-03-18T10:00:00Z",
          cumulative_mm: 100.0
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "both fields present → uses interval_mm", %{
      conn: conn,
      api_key: key,
      sensor_interval: sensor
    } do
      ts = "2026-03-18T10:03:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "rain-interval",
        timestamp: ts,
        interval_mm: 3.0,
        cumulative_mm: 999.0
      })

      from = DateTime.from_iso8601("2026-03-18T09:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T10:10:00Z") |> elem(1)
      readings = Voria2.Measurements.rain_for_sensor!(sensor.id, from, to, authorize?: false)
      assert length(readings) == 1
      assert hd(readings).interval_mm == 3.0
    end

    test "neither field present → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-interval",
          timestamp: "2026-03-18T10:00:00Z"
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "interval_mm negative → 422 (resource constraint)", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-interval",
          timestamp: "2026-03-18T10:00:00Z",
          interval_mm: -1.0
        })

      assert json_response(conn, 422)["ok"] == false
    end

    test "interval_mm is string → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-interval",
          timestamp: "2026-03-18T10:00:00Z",
          interval_mm: "abc"
        })

      assert json_response(conn, 422)["ok"] == false
    end
  end

  # ── Custom tests ──────────────────────────────────────────────────────────────

  describe "custom ingest" do
    setup %{station: station} do
      mt = create_measurement_type(slug: "my_sensor", storage_type: :custom)
      sensor = create_sensor_installation(station, mt)
      Voria2.Cache.invalidate_sensor(station.id, "my_sensor")
      %{sensor: sensor}
    end

    test "{value: 42.0} → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "my_sensor",
          timestamp: "2026-03-18T10:00:00Z",
          value: 42.0
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "{raw: map} → 201", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "my_sensor",
          timestamp: "2026-03-18T10:00:00Z",
          raw: %{a: 1, b: 2}
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "neither value nor raw → 201 (custom allows both nil)", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "my_sensor",
          timestamp: "2026-03-18T10:00:00Z"
        })

      assert json_response(conn, 201)["ok"] == true
    end

    test "unknown sensor slug → 422", %{conn: conn, api_key: key} do
      conn =
        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "nonexistent",
          timestamp: "2026-03-18T10:00:00Z"
        })

      assert json_response(conn, 422)["ok"] == false
      assert json_response(conn, 422)["error"] =~ "unknown sensor slug"
    end
  end

  # ── Bulk tests ────────────────────────────────────────────────────────────────

  describe "bulk ingest" do
    setup %{station: station} do
      mt_temp = create_measurement_type(slug: "temp-bulk", storage_type: :scalar)
      create_sensor_installation(station, mt_temp)
      mt_wind = create_measurement_type(slug: "wind-bulk", storage_type: :wind)
      create_sensor_installation(station, mt_wind)
      mt_humidity = create_measurement_type(slug: "humidity", storage_type: :scalar)
      create_sensor_installation(station, mt_humidity)

      Voria2.Cache.invalidate_sensor(station.id, "temp-bulk")
      Voria2.Cache.invalidate_sensor(station.id, "wind-bulk")
      Voria2.Cache.invalidate_sensor(station.id, "humidity")
      :ok
    end

    test "empty array → 200 count 0", %{conn: conn, api_key: key} do
      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", "[]")
      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["count"] == 0
      assert resp["results"] == []
    end

    test "single valid item → 200 count 1", %{conn: conn, api_key: key} do
      items = [%{sensor: "temp-bulk", timestamp: "2026-03-18T10:00:00Z", value: 20.0}]
      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", Jason.encode!(items))
      resp = json_response(conn, 200)
      assert resp["count"] == 1
    end

    test "5 valid mixed items → 200 count 5", %{conn: conn, api_key: key} do
      items = [
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:00:00Z", value: 20.0},
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:01:00Z", value: 21.0},
        %{sensor: "wind-bulk", timestamp: "2026-03-18T10:02:00Z", u: 1, v: 0},
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:03:00Z", value: 22.0},
        %{sensor: "wind-bulk", timestamp: "2026-03-18T10:04:00Z", u: 0, v: -1}
      ]

      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", Jason.encode!(items))
      assert json_response(conn, 200)["count"] == 5
    end

    test "body is object → 422", %{conn: conn, api_key: key} do
      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", ~s({"sensor":"x"}))
      assert json_response(conn, 422)["ok"] == false
    end

    test "mixed valid/invalid: [valid, invalid, valid] → count 2", %{conn: conn, api_key: key} do
      items = [
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:00:00Z", value: 20.0},
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:01:00Z", value: "bad"},
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:02:00Z", value: 21.0}
      ]

      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", Jason.encode!(items))
      resp = json_response(conn, 200)
      assert resp["count"] == 2
      results = resp["results"]
      assert Enum.at(results, 0)["ok"] == true
      assert Enum.at(results, 1)["ok"] == false
      assert Enum.at(results, 2)["ok"] == true
    end

    test "10 items, first invalid → count 9", %{conn: conn, api_key: key} do
      valid =
        Enum.map(1..9, fn i ->
          %{sensor: "temp-bulk", timestamp: "2026-03-18T10:0#{i}:00Z", value: 20.0 + i}
        end)

      invalid = %{sensor: "nonexistent-slug", timestamp: "2026-03-18T10:00:00Z", value: 1.0}
      items = [invalid | valid]
      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", Jason.encode!(items))
      assert json_response(conn, 200)["count"] == 9
    end

    test "resource validation failure stays isolated in bulk", %{conn: conn, api_key: key} do
      items = [
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:00:00Z", value: 20.0},
        %{sensor: "humidity", timestamp: "2026-03-18T10:01:00Z", value: 255.0},
        %{sensor: "temp-bulk", timestamp: "2026-03-18T10:02:00Z", value: 21.0}
      ]

      conn = auth(conn, key) |> raw_post("/api/v1/ingest/bulk", Jason.encode!(items))
      resp = json_response(conn, 200)

      assert resp["ok"] == true
      assert resp["count"] == 2
      assert Enum.at(resp["results"], 0)["ok"] == true
      assert Enum.at(resp["results"], 1)["ok"] == false
      assert Enum.at(resp["results"], 1)["error"] =~ "humidity cannot exceed 100%"
      assert Enum.at(resp["results"], 2)["ok"] == true
    end
  end

  # ── Scientific accuracy via HTTP ──────────────────────────────────────────────

  describe "scientific accuracy" do
    setup %{station: station} do
      mt_temp = create_measurement_type(slug: "temp-sci", storage_type: :scalar)
      sensor_temp = create_sensor_installation(station, mt_temp)
      mt_wind = create_measurement_type(slug: "wind-sci", storage_type: :wind)
      sensor_wind = create_sensor_installation(station, mt_wind)
      mt_rain = create_measurement_type(slug: "rain-sci", storage_type: :rain)
      sensor_rain = create_sensor_installation(station, mt_rain, rain_mode: :interval)

      Voria2.Cache.invalidate_sensor(station.id, "temp-sci")
      Voria2.Cache.invalidate_sensor(station.id, "wind-sci")
      Voria2.Cache.invalidate_sensor(station.id, "rain-sci")

      %{sensor_temp: sensor_temp, sensor_wind: sensor_wind, sensor_rain: sensor_rain}
    end

    test "POST temperature 23.5 stored correctly", %{
      conn: conn,
      api_key: key,
      sensor_temp: sensor
    } do
      ts = "2026-03-18T08:00:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "temp-sci",
        timestamp: ts,
        value: 23.5
      })

      from = DateTime.from_iso8601("2026-03-18T07:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T08:10:00Z") |> elem(1)

      readings =
        Voria2.Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)

      assert length(readings) == 1
      assert hd(readings).value == 23.5
    end

    test "POST wind u=3, v=-4 → speed ≈ 5.0", %{
      conn: conn,
      api_key: key,
      sensor_wind: sensor
    } do
      ts = "2026-03-18T08:01:00Z"

      auth(conn, key)
      |> json_post("/api/v1/ingest", %{
        sensor: "wind-sci",
        timestamp: ts,
        u: 3,
        v: -4
      })

      from = DateTime.from_iso8601("2026-03-18T07:50:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T08:10:00Z") |> elem(1)

      readings =
        Voria2.Measurements.WindMeasurement
        |> Ash.Query.filter(
          sensor_installation_id == ^sensor.id and measured_at >= ^from and measured_at <= ^to
        )
        |> Ash.Query.load([:speed, :direction_deg])
        |> Ash.read!(authorize?: false)

      assert length(readings) == 1
      assert_in_delta hd(readings).speed, 5.0, 0.001
    end

    test "POST rain intervals stored correctly", %{
      conn: conn,
      api_key: key,
      sensor_rain: sensor
    } do
      base = "2026-03-18T08:"

      for {mm, i} <- Enum.with_index([0.0, 5.0, 0.0]) do
        ts = "#{base}0#{i}:00Z"

        auth(conn, key)
        |> json_post("/api/v1/ingest", %{
          sensor: "rain-sci",
          timestamp: ts,
          interval_mm: mm
        })
      end

      from = DateTime.from_iso8601("2026-03-18T08:00:00Z") |> elem(1)
      to = DateTime.from_iso8601("2026-03-18T09:00:00Z") |> elem(1)
      readings = Voria2.Measurements.rain_for_sensor!(sensor.id, from, to, authorize?: false)

      assert length(readings) == 3
      assert Enum.map(readings, & &1.interval_mm) == [0.0, 5.0, 0.0]
    end
  end
end
