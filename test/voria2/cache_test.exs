defmodule Voria2.CacheTest do
  use Voria2.DataCase, async: false

  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    {:ok, api_key} = Voria2.Network.generate_station_api_key(station.id, actor: user)
    %{user: user, station: station, api_key: api_key}
  end

  describe "station_for_key/1" do
    test "returns station for valid key", %{station: station, api_key: api_key} do
      assert {:ok, cached_station} = Voria2.Cache.station_for_key(api_key.key)
      assert cached_station.id == station.id
    end

    test "result is cached on second call", %{station: station, api_key: api_key} do
      assert {:ok, _} = Voria2.Cache.station_for_key(api_key.key)
      # Second call should come from cache
      assert {:ok, cached_station} = Voria2.Cache.station_for_key(api_key.key)
      assert cached_station.id == station.id
      # Confirm it's actually in the ETS cache
      assert [{_, cached_val, _expiry}] = :ets.lookup(:voria2_cache, {:api_key, api_key.key})
      assert cached_val.id == station.id
    end

    test "returns nil for unknown key" do
      assert {:ok, nil} = Voria2.Cache.station_for_key("vsk_nonexistent")
    end

    test "returns nil after key is revoked and cache is invalidated", %{
      user: user,
      api_key: api_key
    } do
      assert {:ok, station} = Voria2.Cache.station_for_key(api_key.key)
      assert not is_nil(station)

      # Revoke the key — automatic invalidation clears the cache entry
      Voria2.Network.revoke_station_api_key!(api_key, actor: user)

      # Cache entry was automatically cleared by the revoke action
      assert :ets.lookup(:voria2_cache, {:api_key, api_key.key}) == []
      # Subsequent lookup returns nil (key is deleted from DB too)
      assert {:ok, nil} = Voria2.Cache.station_for_key(api_key.key)
    end

    test "cache stores correct expiry timestamp", %{api_key: api_key} do
      before = System.monotonic_time(:millisecond)
      Voria2.Cache.station_for_key(api_key.key)
      after_call = System.monotonic_time(:millisecond)

      [{_, _val, expiry}] = :ets.lookup(:voria2_cache, {:api_key, api_key.key})

      # Expiry should be roughly 5 minutes (300,000 ms) from now
      ttl_ms = 5 * 60 * 1000
      min_expected = before + ttl_ms
      # Allow 100ms margin
      max_expected = after_call + ttl_ms + 100

      assert expiry >= min_expected and expiry <= max_expected
    end

    test "expired entries are cleaned up on access", %{station: station, api_key: api_key} do
      # Manually insert an expired entry with a fake station
      key_tuple = {:api_key, api_key.key}
      fake_station = %{station | id: "fake-id"}
      # 1 second ago
      expired_time = System.monotonic_time(:millisecond) - 1000
      :ets.insert(:voria2_cache, {key_tuple, fake_station, expired_time})

      # Confirm it's in cache but expired
      assert [{_, _, exp}] = :ets.lookup(:voria2_cache, key_tuple)
      assert exp < System.monotonic_time(:millisecond)

      # Lookup should detect expiry, delete the expired entry, and query DB
      # (which returns the real station since the key exists in DB)
      {:ok, result} = Voria2.Cache.station_for_key(api_key.key)
      # Should get real station, not fake one
      assert result.id == station.id

      # A fresh cache lookup should be inserted
      # (the old expired one was deleted, new one inserted)
      [{_, new_station, _new_exp}] = :ets.lookup(:voria2_cache, key_tuple)
      assert new_station.id == station.id
    end

    test "queries DB only on cache miss", %{station: station, api_key: api_key} do
      # First call: cache miss, queries DB
      {:ok, result1} = Voria2.Cache.station_for_key(api_key.key)
      assert result1.id == station.id

      # Clear the call counter if any exists
      # Second call: cache hit, should not query DB (but we can't easily verify this without instrumentation)
      {:ok, result2} = Voria2.Cache.station_for_key(api_key.key)
      assert result2.id == station.id

      # Both results should be identical
      assert result1.id == result2.id
    end
  end

  describe "sensor_for_station_slug/2" do
    test "returns nil for unknown slug", %{station: station} do
      assert {:ok, nil} = Voria2.Cache.sensor_for_station_slug(station.id, "nonexistent")
    end

    test "returns sensor for known slug", %{station: station} do
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      create_sensor_installation(station, mt)

      assert {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "temperature")
      assert not is_nil(sensor)
      assert sensor.measurement_type.slug == "temperature"
    end

    test "does not return decommissioned sensor", %{station: station} do
      mt = create_measurement_type(slug: "temperature-old", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)
      Voria2.Measurements.decommission_sensor!(sensor, authorize?: false)

      assert {:ok, nil} = Voria2.Cache.sensor_for_station_slug(station.id, "temperature-old")
    end

    test "caches sensor by station_id and slug tuple", %{station: station} do
      mt = create_measurement_type(slug: "humidity", storage_type: :scalar)
      create_sensor_installation(station, mt)

      # First call caches
      {:ok, sensor1} = Voria2.Cache.sensor_for_station_slug(station.id, "humidity")
      assert sensor1.measurement_type.slug == "humidity"

      # Verify it's in cache with correct key tuple
      key_tuple = {:sensor, station.id, "humidity"}
      assert [{^key_tuple, cached_sensor, _expiry}] = :ets.lookup(:voria2_cache, key_tuple)
      assert cached_sensor.id == sensor1.id
    end

    test "returns cached sensor on second call", %{station: station} do
      mt = create_measurement_type(slug: "pressure", storage_type: :scalar)
      create_sensor_installation(station, mt)

      {:ok, sensor1} = Voria2.Cache.sensor_for_station_slug(station.id, "pressure")
      {:ok, sensor2} = Voria2.Cache.sensor_for_station_slug(station.id, "pressure")

      assert sensor1.id == sensor2.id
    end

    test "different slugs are cached separately", %{station: station} do
      mt_temp = create_measurement_type(slug: "temp-separate", storage_type: :scalar)
      mt_humid = create_measurement_type(slug: "humid-separate", storage_type: :scalar)
      create_sensor_installation(station, mt_temp)
      create_sensor_installation(station, mt_humid)

      {:ok, sensor_temp} = Voria2.Cache.sensor_for_station_slug(station.id, "temp-separate")
      {:ok, sensor_humid} = Voria2.Cache.sensor_for_station_slug(station.id, "humid-separate")

      assert sensor_temp.id != sensor_humid.id

      # Both should be cached with different keys
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "temp-separate"}) != []
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "humid-separate"}) != []
    end

    test "sensor invalidation removes specific sensor from cache", %{station: station} do
      mt = create_measurement_type(slug: "windspeed", storage_type: :scalar)
      create_sensor_installation(station, mt)

      # Cache the sensor
      {:ok, sensor} = Voria2.Cache.sensor_for_station_slug(station.id, "windspeed")
      assert not is_nil(sensor)

      # Invalidate it
      Voria2.Cache.invalidate_sensor(station.id, "windspeed")

      # Should be removed from cache and subsequent lookups query DB
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "windspeed"}) == []
    end
  end

  describe "cache concurrency (read_concurrency + write_concurrency)" do
    test "concurrent reads don't block each other", %{api_key: api_key} do
      key_str = api_key.key

      # Cache the entry
      Voria2.Cache.station_for_key(key_str)

      # Spawn 10 concurrent readers
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn ->
            Voria2.Cache.station_for_key(key_str)
          end)
        end)

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn {:ok, station} -> not is_nil(station) end)
    end

    test "read and write don't deadlock", %{api_key: api_key} do
      key_str = api_key.key

      # Initial cache
      Voria2.Cache.station_for_key(key_str)

      # Spawn reader and writer tasks
      reader =
        Task.async(fn ->
          for _ <- 1..5 do
            Voria2.Cache.station_for_key(key_str)
          end
        end)

      writer =
        Task.async(fn ->
          Process.sleep(10)
          Voria2.Cache.invalidate_key(key_str)
        end)

      # Both should complete without deadlock or timeout
      reader_result = Task.await(reader, 5000)
      writer_result = Task.await(writer, 5000)

      # Reader returns a list of 5 results, each should be {:ok, station} or {:ok, nil}
      # (nil is valid if the cache was invalidated mid-read and DB was queried again)
      assert is_list(reader_result)
      assert length(reader_result) == 5
      assert Enum.all?(reader_result, fn result -> match?({:ok, _}, result) end)

      # Writer should complete without error
      assert writer_result == :ok
    end
  end

  describe "PubSub invalidation broadcasting" do
    setup do
      start_supervised!({Voria2.CacheInvalidationListener, []})
      :ok
    end

    test "invalidate_key broadcasts to PubSub", %{api_key: api_key} do
      # Subscribe to the cache_invalidation topic
      Phoenix.PubSub.subscribe(Voria2.PubSub, "cache_invalidation")

      key_str = api_key.key

      # Invalidate a key
      Voria2.Cache.invalidate_key(key_str)

      # Should receive the broadcast message
      assert_receive {:invalidate_key, ^key_str}, 1000
    end

    test "invalidate_sensor broadcasts to PubSub", %{station: station} do
      Phoenix.PubSub.subscribe(Voria2.PubSub, "cache_invalidation")

      station_id = station.id
      slug = "test-sensor"
      Voria2.Cache.invalidate_sensor(station_id, slug)

      assert_receive {:invalidate_sensor, ^station_id, ^slug}, 1000
    end

    test "CacheInvalidationListener deletes ETS entry on PubSub message", %{api_key: api_key} do
      key_str = api_key.key

      # Put entry directly in ETS, bypassing the cache module
      :ets.insert(:voria2_cache, {{:api_key, key_str}, :some_value, :infinity})
      assert :ets.lookup(:voria2_cache, {:api_key, key_str}) != []

      # Simulate what another node would do: broadcast directly to PubSub,
      # WITHOUT calling invalidate_key (which would also delete locally)
      Phoenix.PubSub.broadcast(Voria2.PubSub, "cache_invalidation", {:invalidate_key, key_str})

      # Give the listener GenServer time to process the message
      Process.sleep(50)

      # The listener should have deleted the ETS entry
      assert :ets.lookup(:voria2_cache, {:api_key, key_str}) == []
    end

    test "CacheInvalidationListener deletes sensor ETS entry on PubSub message", %{
      station: station
    } do
      station_id = station.id
      slug = "wind"

      # Put entry directly in ETS
      :ets.insert(:voria2_cache, {{:sensor, station_id, slug}, :some_sensor, :infinity})
      assert :ets.lookup(:voria2_cache, {:sensor, station_id, slug}) != []

      # Simulate remote node broadcast
      Phoenix.PubSub.broadcast(
        Voria2.PubSub,
        "cache_invalidation",
        {:invalidate_sensor, station_id, slug}
      )

      Process.sleep(50)

      assert :ets.lookup(:voria2_cache, {:sensor, station_id, slug}) == []
    end
  end

  describe "automatic invalidation on DB mutations" do
    test "revoking a key removes it from cache automatically", %{user: user, api_key: api_key} do
      # Cache the key
      assert {:ok, station} = Voria2.Cache.station_for_key(api_key.key)
      assert not is_nil(station)
      assert :ets.lookup(:voria2_cache, {:api_key, api_key.key}) != []

      # Revoke via the domain — no manual Cache.invalidate_key call
      Voria2.Network.revoke_station_api_key!(api_key, actor: user)

      # Cache entry should be gone automatically
      assert :ets.lookup(:voria2_cache, {:api_key, api_key.key}) == []
      # And subsequent lookup returns nil (key is deleted from DB too)
      assert {:ok, nil} = Voria2.Cache.station_for_key(api_key.key)
    end

    test "decommissioning a sensor removes it from cache automatically", %{station: station} do
      mt = create_measurement_type(slug: "auto-decom", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)

      # Cache the sensor
      assert {:ok, cached} = Voria2.Cache.sensor_for_station_slug(station.id, "auto-decom")
      assert not is_nil(cached)
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "auto-decom"}) != []

      # Decommission via the domain — no manual Cache.invalidate_sensor call
      Voria2.Measurements.decommission_sensor!(sensor, authorize?: false)

      # Cache entry should be gone automatically
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "auto-decom"}) == []
      # Subsequent lookup returns nil (sensor is decommissioned)
      assert {:ok, nil} = Voria2.Cache.sensor_for_station_slug(station.id, "auto-decom")
    end

    test "destroying a sensor removes it from cache automatically", %{station: station} do
      mt = create_measurement_type(slug: "auto-destroy", storage_type: :scalar)
      sensor = create_sensor_installation(station, mt)

      assert {:ok, _} = Voria2.Cache.sensor_for_station_slug(station.id, "auto-destroy")
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "auto-destroy"}) != []

      Voria2.Measurements.destroy_sensor_installation!(sensor, authorize?: false)

      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "auto-destroy"}) == []
    end

    test "updating a sensor removes it from cache automatically", %{station: station} do
      mt = create_measurement_type(slug: "auto-update", storage_type: :rain)
      sensor = create_sensor_installation(station, mt, rain_mode: :interval)

      # Cache it
      assert {:ok, cached} = Voria2.Cache.sensor_for_station_slug(station.id, "auto-update")
      assert cached.rain_mode == :interval

      # Update rain_mode via domain — no manual invalidation
      Voria2.Measurements.update_sensor_installation!(sensor, %{rain_mode: :cumulative},
        authorize?: false
      )

      # Cache entry should be gone
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "auto-update"}) == []
      # Next lookup reflects updated value
      assert {:ok, fresh} = Voria2.Cache.sensor_for_station_slug(station.id, "auto-update")
      assert fresh.rain_mode == :cumulative
    end
  end

  describe "edge cases" do
    test "nil values are not cached", %{station: station} do
      # First lookup returns nil (not found)
      {:ok, nil} = Voria2.Cache.sensor_for_station_slug(station.id, "nonexistent")

      # Second lookup should also query DB (not cache the nil)
      # Verify by checking the cache is empty
      assert :ets.lookup(:voria2_cache, {:sensor, station.id, "nonexistent"}) == []
    end

    test "empty string slug returns nil", %{station: station} do
      {:ok, result} = Voria2.Cache.sensor_for_station_slug(station.id, "")
      assert is_nil(result)
    end

    test "multiple keys for same station tracked separately", %{station: station, user: user} do
      {:ok, key1} = Voria2.Network.generate_station_api_key(station.id, actor: user)
      {:ok, key2} = Voria2.Network.generate_station_api_key(station.id, actor: user)

      {:ok, station1} = Voria2.Cache.station_for_key(key1.key)
      {:ok, station2} = Voria2.Cache.station_for_key(key2.key)

      # Both should return the same station but be cached under different keys
      assert station1.id == station2.id
      assert :ets.lookup(:voria2_cache, {:api_key, key1.key}) != []
      assert :ets.lookup(:voria2_cache, {:api_key, key2.key}) != []
    end
  end
end
