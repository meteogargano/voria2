defmodule Voria2.SummaryCacheTest do
  use Voria2.DataCase, async: false

  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    %{user: user, station: station}
  end

  # ── get_or_compute_summary ────────────────────────────────────────────────

  describe "get_or_compute_summary/2" do
    test "computes and stores in ETS on cache miss", %{station: station} do
      # No data in cache
      :ets.delete(:voria2_cache, {:summary, :temperature, station.id})

      {:ok, result} = Voria2.Cache.get_or_compute_summary(station.id, :temperature)

      # Result is a struct (may be nil if no data, but the call succeeds)
      assert is_nil(result) or is_struct(result)
    end

    test "stores non-nil result in ETS", %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      record_temperature!(sensor, 20.0)

      :ets.delete(:voria2_cache, {:summary, :temperature, station.id})

      {:ok, result} = Voria2.Cache.get_or_compute_summary(station.id, :temperature)

      assert not is_nil(result)

      assert [{_, cached, _expiry}] =
               :ets.lookup(:voria2_cache, {:summary, :temperature, station.id})

      assert cached == result
    end

    test "returns cached value on second call", %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      record_temperature!(sensor, 21.5)

      :ets.delete(:voria2_cache, {:summary, :temperature, station.id})

      {:ok, first} = Voria2.Cache.get_or_compute_summary(station.id, :temperature)
      assert not is_nil(first)

      # Insert a sentinel to confirm second call reads from cache, not DB
      sentinel = %{sentinel: true}

      :ets.insert(
        :voria2_cache,
        {{:summary, :temperature, station.id}, sentinel,
         System.monotonic_time(:millisecond) + 300_000}
      )

      {:ok, second} = Voria2.Cache.get_or_compute_summary(station.id, :temperature)
      assert second == sentinel
    end

    test "nil result (no data) is not cached", %{station: station} do
      :ets.delete(:voria2_cache, {:summary, :temperature, station.id})

      {:ok, result} = Voria2.Cache.get_or_compute_summary(station.id, :temperature)

      # If the summary returns nil (no sensors/data), it should not be cached
      if is_nil(result) do
        assert :ets.lookup(:voria2_cache, {:summary, :temperature, station.id}) == []
      end
    end
  end

  # ── put_summary / invalidate_summary ─────────────────────────────────────

  describe "put_summary/3 and invalidate_summary/2" do
    test "put_summary stores value in ETS", %{station: station} do
      value = %{test: "data"}
      Voria2.Cache.put_summary(station.id, :wind, value)

      assert [{_, ^value, _expiry}] = :ets.lookup(:voria2_cache, {:summary, :wind, station.id})
    end

    test "invalidate_summary removes ETS entry", %{station: station} do
      Voria2.Cache.put_summary(station.id, :rain, %{some: "summary"})
      assert :ets.lookup(:voria2_cache, {:summary, :rain, station.id}) != []

      Voria2.Cache.invalidate_summary(station.id, :rain)

      assert :ets.lookup(:voria2_cache, {:summary, :rain, station.id}) == []
    end

    test "invalidating one type leaves others intact", %{station: station} do
      Voria2.Cache.put_summary(station.id, :temperature, %{a: 1})
      Voria2.Cache.put_summary(station.id, :wind, %{b: 2})

      Voria2.Cache.invalidate_summary(station.id, :temperature)

      assert :ets.lookup(:voria2_cache, {:summary, :temperature, station.id}) == []
      assert :ets.lookup(:voria2_cache, {:summary, :wind, station.id}) != []
    end
  end

  # ── broadcast_measurement ─────────────────────────────────────────────────

  describe "broadcast_measurement/3" do
    setup %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "temperature")
      %{sensor: sensor}
    end

    test "broadcasts to 'measurements' topic", %{station: station, sensor: sensor} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      ts = DateTime.utc_now()

      Voria2.Cache.broadcast_measurement(station.id, sensor, ts)

      station_id = station.id

      assert_receive {:new_measurement, %{station_id: ^station_id, summary_type: :temperature}},
                     1000
    end

    test "broadcasts to 'station:id' topic", %{station: station, sensor: sensor} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "station:#{station.id}")
      ts = DateTime.utc_now()

      Voria2.Cache.broadcast_measurement(station.id, sensor, ts)

      station_id = station.id
      assert_receive {:new_measurement, %{station_id: ^station_id}}, 1000
    end

    test "temperature slug maps to :temperature summary_type", %{station: station, sensor: sensor} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")

      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: :temperature}}, 1000
    end
  end

  describe "broadcast_measurement/3 summary_type mapping" do
    test "humidity slug maps to :humidity_pressure", %{station: station} do
      mt = create_measurement_type(slug: "humidity", storage_type: :scalar)
      create_sensor_installation(station, mt)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "humidity")

      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: :humidity_pressure}}, 1000
    end

    test "pressure slug maps to :humidity_pressure", %{station: station} do
      mt = create_measurement_type(slug: "pressure", storage_type: :scalar)
      create_sensor_installation(station, mt)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "pressure")

      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: :humidity_pressure}}, 1000
    end

    test "wind storage_type maps to :wind", %{station: station} do
      mt = create_measurement_type(slug: "wind-speed", storage_type: :wind)
      create_sensor_installation(station, mt)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "wind-speed")

      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: :wind}}, 1000
    end

    test "rain storage_type maps to :rain", %{station: station} do
      mt = create_measurement_type(slug: "rain-gauge", storage_type: :rain)
      create_sensor_installation(station, mt, rain_mode: :interval)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "rain-gauge")

      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: :rain}}, 1000
    end

    test "custom storage_type maps to nil summary_type", %{station: station} do
      mt = create_measurement_type(slug: "co2", storage_type: :custom)
      create_sensor_installation(station, mt)
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "co2")

      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
      Voria2.Cache.broadcast_measurement(station.id, sensor, DateTime.utc_now())

      assert_receive {:new_measurement, %{summary_type: nil}}, 1000
    end
  end

  # ── CacheInvalidationListener ─────────────────────────────────────────────

  describe "CacheInvalidationListener handles :new_measurement" do
    setup do
      start_supervised!({Voria2.CacheInvalidationListener, []})
      :ok
    end

    test "invalidates ETS entry on broadcast (sentinel replaced by recomputed value)", %{
      station: station
    } do
      # Directly insert a recognizable sentinel
      :ets.insert(
        :voria2_cache,
        {{:summary, :temperature, station.id}, :sentinel_value, :infinity}
      )

      event = %{
        station_id: station.id,
        sensor_id: "x",
        summary_type: :temperature,
        measured_at: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Voria2.PubSub, "measurements", {:new_measurement, event})

      # Wait for listener + warm-up task to complete
      Process.sleep(200)

      # The sentinel must be gone — either evicted (empty) or replaced by a real struct
      case :ets.lookup(:voria2_cache, {:summary, :temperature, station.id}) do
        [] -> :ok
        [{_, value, _}] -> assert value != :sentinel_value
      end
    end

    test "nil summary_type events are ignored (no ETS delete attempted)", %{station: station} do
      :ets.insert(:voria2_cache, {{:summary, :temperature, station.id}, :sentinel, :infinity})

      event = %{
        station_id: station.id,
        sensor_id: "x",
        summary_type: nil,
        measured_at: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Voria2.PubSub, "measurements", {:new_measurement, event})

      Process.sleep(50)

      # Temperature entry should still be present (nil type was ignored)
      assert :ets.lookup(:voria2_cache, {:summary, :temperature, station.id}) != []
    end

    test "warm-up task re-populates cache after invalidation", %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      record_temperature!(sensor, 18.0)

      # Ensure no cached entry
      :ets.delete(:voria2_cache, {:summary, :temperature, station.id})

      event = %{
        station_id: station.id,
        sensor_id: sensor.id,
        summary_type: :temperature,
        measured_at: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Voria2.PubSub, "measurements", {:new_measurement, event})

      # Wait for the supervised Task to complete
      Process.sleep(200)

      assert [{_, value, _expiry}] =
               :ets.lookup(:voria2_cache, {:summary, :temperature, station.id})

      assert not is_nil(value)
    end
  end

  # ── Ingest integration ────────────────────────────────────────────────────

  describe "Ingest.dispatch broadcasts new_measurement" do
    setup %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      %{sensor: sensor}
    end

    test "successful ingest broadcasts to 'measurements' topic", %{station: station} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")

      params = %{
        "sensor" => "temperature",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "value" => 22.5
      }

      assert :ok = Voria2.Ingest.dispatch(station, params)

      station_id = station.id

      assert_receive {:new_measurement, %{station_id: ^station_id, summary_type: :temperature}},
                     1000
    end

    test "successful ingest broadcasts to 'station:id' topic", %{station: station} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "station:#{station.id}")

      params = %{
        "sensor" => "temperature",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "value" => 23.0
      }

      assert :ok = Voria2.Ingest.dispatch(station, params)

      station_id = station.id
      assert_receive {:new_measurement, %{station_id: ^station_id}}, 1000
    end

    test "failed ingest does not broadcast", %{station: station} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")

      # Missing value field — dispatch will fail
      params = %{
        "sensor" => "temperature",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      assert {:error, _} = Voria2.Ingest.dispatch(station, params)

      refute_receive {:new_measurement, _}, 100
    end
  end

  # ── TTL expiry ────────────────────────────────────────────────────────────

  describe "summary TTL expiry" do
    test "expired summary is treated as a miss", %{station: station} do
      sentinel = %{expired: true}
      expired_time = System.monotonic_time(:millisecond) - 1000
      :ets.insert(:voria2_cache, {{:summary, :wind, station.id}, sentinel, expired_time})

      # Should detect expiry and re-compute (returns DB result, not sentinel)
      {:ok, result} = Voria2.Cache.get_or_compute_summary(station.id, :wind)

      refute result == sentinel
      # The expired entry should be gone from ETS
      # (either deleted on miss, or replaced with fresh nil)
      case :ets.lookup(:voria2_cache, {:summary, :wind, station.id}) do
        [{_, val, _}] -> refute val == sentinel
        [] -> :ok
      end
    end
  end
end
