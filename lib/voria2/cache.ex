defmodule Voria2.Cache do
  require Ash.Query

  @table :voria2_cache
  @key_ttl 5 * 60 * 1000
  @sensor_ttl 5 * 60 * 1000
  @summary_ttl 5 * 60 * 1000
  @webcam_ttl 5 * 60 * 1000
  @dailylog_ttl 5 * 60 * 1000
  @warm_lock_ttl_ms 30_000

  def init_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      _ ->
        @table
    end
  end

  # ─── Warm dedup lock ────────────────────────────────────────────────────
  # Soft in-flight lock so duplicate warm tasks for the same key are skipped.
  # If a task is already warming this key, claim_warm/1 returns false and the
  # caller skips spawning a redundant task. The TTL self-heals any lock leaked
  # by a crashed task. Benign race: at most an occasional double-warm (the same
  # behavior as today without any dedup) — never incorrect data.

  def claim_warm(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, {:warm_lock, key}) do
      [{_, expiry}] when expiry > now ->
        false

      _ ->
        :ets.insert(@table, {{:warm_lock, key}, now + @warm_lock_ttl_ms})
        true
    end
  end

  def release_warm(key), do: :ets.delete(@table, {:warm_lock, key})

  # Returns {:ok, station} | {:ok, nil}
  def station_for_key(api_key) do
    case lookup_with_ttl({:api_key, api_key}) do
      {:ok, station} ->
        {:ok, station}

      :expired_or_missing ->
        # Fetch from DB and cache
        case Voria2.Network.get_station_api_key_by_key(api_key,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, key_record} ->
            case Ash.get(Voria2.Network.Station, key_record.station_id, authorize?: false) do
              {:ok, station} ->
                store_with_ttl({:api_key, api_key}, station, @key_ttl)
                {:ok, station}

              _ ->
                {:ok, nil}
            end

          _ ->
            {:ok, nil}
        end
    end
  end

  # Returns {:ok, sensor_installation_with_measurement_type} | {:ok, nil}
  def sensor_for_station_slug(station_id, slug) do
    case lookup_with_ttl({:sensor, station_id, slug}) do
      {:ok, sensor} ->
        {:ok, sensor}

      :expired_or_missing ->
        found =
          Voria2.Measurements.SensorInstallation
          |> Ash.Query.filter(station_id == ^station_id)
          |> Ash.Query.load(:measurement_type)
          |> Ash.read!(authorize?: false)
          |> Enum.find(fn s ->
            s.measurement_type.slug == slug and is_nil(s.removed_at)
          end)

        if found do
          store_with_ttl({:sensor, station_id, slug}, found, @sensor_ttl)
          {:ok, found}
        else
          {:ok, nil}
        end
    end
  end

  def invalidate_key(api_key) do
    :ets.delete(@table, {:api_key, api_key})
    # Broadcast invalidation to all nodes
    Phoenix.PubSub.broadcast(Voria2.PubSub, "cache_invalidation", {:invalidate_key, api_key})
  end

  def invalidate_sensor(station_id, slug) do
    :ets.delete(@table, {:sensor, station_id, slug})
    # Broadcast invalidation to all nodes
    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      "cache_invalidation",
      {:invalidate_sensor, station_id, slug}
    )
  end

  # ─── Webcam cache ───────────────────────────────────────────────────────

  # Returns {:ok, webcam} | {:ok, nil}
  def webcam_for_key(api_key) do
    case lookup_with_ttl({:webcam_key, api_key}) do
      {:ok, webcam} ->
        {:ok, webcam}

      :expired_or_missing ->
        case Voria2.Network.get_webcam_api_key_by_key(api_key,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, key_record} ->
            case Ash.get(Voria2.Network.Webcam, key_record.webcam_id, authorize?: false) do
              {:ok, webcam} ->
                store_with_ttl({:webcam_key, api_key}, webcam, @webcam_ttl)
                {:ok, webcam}

              _ ->
                {:ok, nil}
            end

          _ ->
            {:ok, nil}
        end
    end
  end

  # Returns {:ok, shot | nil}
  def latest_shot_for_webcam(webcam_id) do
    case lookup_with_ttl({:latest_shot, webcam_id}) do
      {:ok, shot} ->
        {:ok, shot}

      :expired_or_missing ->
        shot =
          case Voria2.Network.latest_webcam_shot(webcam_id, authorize?: false) do
            {:ok, [shot | _]} -> shot
            {:ok, []} -> nil
            _ -> nil
          end

        store_with_ttl({:latest_shot, webcam_id}, shot, @webcam_ttl)
        {:ok, shot}
    end
  end

  # Returns {:ok, [%{webcam: w, latest_shot: s | nil}]}
  def all_webcams_latest_shots do
    case lookup_with_ttl({:all_webcams_latest}) do
      {:ok, list} ->
        {:ok, list}

      :expired_or_missing ->
        list = compute_all_webcams_latest()
        store_with_ttl({:all_webcams_latest}, list, @webcam_ttl)
        {:ok, list}
    end
  end

  def warm_latest_shot(webcam_id) do
    shot =
      case Voria2.Network.latest_webcam_shot(webcam_id, authorize?: false) do
        {:ok, [shot | _]} -> shot
        {:ok, []} -> nil
        _ -> nil
      end

    store_with_ttl({:latest_shot, webcam_id}, shot, @webcam_ttl)
    :ok
  end

  def warm_all_webcams_latest do
    list = compute_all_webcams_latest()
    store_with_ttl({:all_webcams_latest}, list, @webcam_ttl)
    :ok
  end

  # ─── Webcam shot bytes cache ────────────────────────────────────────────

  # Returns {:ok, %{body: binary, content_type: String.t()} | nil}
  def latest_shot_bytes_for_webcam(webcam_id) do
    case lookup_with_ttl({:latest_shot_bytes, webcam_id}) do
      {:ok, value} ->
        {:ok, value}

      :expired_or_missing ->
        value = compute_latest_shot_bytes(webcam_id)
        store_with_ttl({:latest_shot_bytes, webcam_id}, value, @webcam_ttl)
        {:ok, value}
    end
  end

  def warm_latest_shot_bytes(webcam_id) do
    value = compute_latest_shot_bytes(webcam_id)
    store_with_ttl({:latest_shot_bytes, webcam_id}, value, @webcam_ttl)
    :ok
  end

  def warm_all_latest_shot_bytes do
    webcams =
      Voria2.Network.Webcam
      |> Ash.Query.filter(is_active == true)
      |> Ash.read!(authorize?: false)

    Enum.each(webcams, fn webcam ->
      warm_latest_shot_bytes(webcam.id)
    end)

    :ok
  end

  def invalidate_webcam_key(api_key) do
    :ets.delete(@table, {:webcam_key, api_key})

    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      "cache_invalidation",
      {:invalidate_webcam_key, api_key}
    )
  end

  def invalidate_latest_shot(webcam_id) do
    :ets.delete(@table, {:latest_shot, webcam_id})
    :ets.delete(@table, {:latest_shot_bytes, webcam_id})
    :ets.delete(@table, {:all_webcams_latest})

    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      "cache_invalidation",
      {:invalidate_latest_shot, webcam_id}
    )
  end

  def broadcast_webcam_shot(webcam_id) do
    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      "webcam_shots",
      {:new_webcam_shot, %{webcam_id: webcam_id}}
    )
  end

  # ─── Summary cache ──────────────────────────────────────────────────────

  # Cache-first lookup; computes and stores on miss.
  def get_or_compute_summary(station_id, summary_type) do
    case lookup_with_ttl({:summary, summary_type, station_id}) do
      {:ok, value} ->
        {:ok, value}

      :expired_or_missing ->
        value = compute_summary(station_id, summary_type)

        if not is_nil(value) do
          store_with_ttl({:summary, summary_type, station_id}, value, @summary_ttl)
        end

        {:ok, value}
    end
  end

  # Called by CacheInvalidationListener warm-up tasks after invalidation.
  def warm_summary(station_id, summary_type) do
    value = compute_summary(station_id, summary_type)

    if not is_nil(value) do
      store_with_ttl({:summary, summary_type, station_id}, value, @summary_ttl)
    end

    :ok
  end

  def put_summary(station_id, summary_type, value) do
    store_with_ttl({:summary, summary_type, station_id}, value, @summary_ttl)
  end

  def invalidate_summary(station_id, summary_type) do
    :ets.delete(@table, {:summary, summary_type, station_id})
  end

  # ─── Daily log cache ─────────────────────────────────────────────────────

  def get_or_compute_dailylog(station) do
    {scope, date} = Voria2.Measurements.DailyLog.cache_scope_for_station(station)
    key = {:dailylog, station.id, scope, date}

    case lookup_with_ttl(key) do
      {:ok, value} ->
        {:ok, value}

      :expired_or_missing ->
        value = Voria2.Measurements.DailyLog.render_for_station(station)
        store_with_ttl(key, value, @dailylog_ttl)
        {:ok, value}
    end
  end

  def warm_dailylog(station, measured_at \\ nil) do
    _ = measured_at
    {scope, date} = Voria2.Measurements.DailyLog.cache_scope_for_station(station)
    value = Voria2.Measurements.DailyLog.render_for_station(station)
    store_with_ttl({:dailylog, station.id, scope, date}, value, @dailylog_ttl)

    :ok
  end

  def invalidate_dailylog(station, measured_at \\ nil) do
    Enum.each(
      Voria2.Measurements.DailyLog.invalidate_keys_for_station(station, measured_at),
      fn {scope, date} ->
        :ets.delete(@table, {:dailylog, station.id, scope, date})
      end
    )
  end

  # Broadcasts a new_measurement event to both the global and per-station topics.
  def broadcast_measurement(station_id, sensor, measured_at) do
    summary_type =
      slug_to_summary_type(
        sensor.measurement_type.storage_type,
        sensor.measurement_type.slug
      )

    event = %{
      station_id: station_id,
      sensor_id: sensor.id,
      summary_type: summary_type,
      measured_at: measured_at
    }

    Phoenix.PubSub.broadcast(Voria2.PubSub, "measurements", {:new_measurement, event})
    Phoenix.PubSub.broadcast(Voria2.PubSub, "station:#{station_id}", {:new_measurement, event})
  end

  # ─── Heartbeat tracking ─────────────────────────────────────────────────

  def touch_station(station_id) do
    :ets.insert(@table, {{:station_heartbeat, station_id}, DateTime.utc_now()})
  end

  def touch_webcam(webcam_id) do
    :ets.insert(@table, {{:webcam_heartbeat, webcam_id}, DateTime.utc_now()})
  end

  def station_last_seen(station_id) do
    case :ets.lookup(@table, {:station_heartbeat, station_id}) do
      [{_, dt}] -> dt
      [] -> nil
    end
  end

  def webcam_last_seen(webcam_id) do
    case :ets.lookup(@table, {:webcam_heartbeat, webcam_id}) do
      [{_, dt}] -> dt
      [] -> nil
    end
  end

  # ─── Internals ─────────────────────────────────────────────────────────

  defp compute_all_webcams_latest do
    webcams =
      Voria2.Network.Webcam
      |> Ash.Query.filter(is_active == true)
      |> Ash.read!(authorize?: false)

    Enum.map(webcams, fn webcam ->
      shot =
        case Voria2.Network.latest_webcam_shot(webcam.id, authorize?: false) do
          {:ok, [shot | _]} -> shot
          {:ok, []} -> nil
          _ -> nil
        end

      %{webcam: webcam, latest_shot: shot}
    end)
  end

  defp compute_latest_shot_bytes(webcam_id) do
    case latest_shot_for_webcam(webcam_id) do
      {:ok, nil} ->
        nil

      {:ok, shot} ->
        case Voria2.Storage.download(shot.s3_key, shot.s3_bucket) do
          {:ok, %{body: body}} ->
            %{body: body, content_type: shot_content_type(shot.s3_key)}

          _ ->
            nil
        end
    end
  end

  defp shot_content_type(s3_key) do
    case MIME.from_path(s3_key) do
      "application/octet-stream" -> "image/webp"
      other -> other
    end
  end

  defp compute_summary(station_id, :temperature) do
    case Voria2.Measurements.temperature_summary(station_id, authorize?: false) do
      {:ok, summary} -> summary
      _ -> nil
    end
  end

  defp compute_summary(station_id, :humidity_pressure) do
    case Voria2.Measurements.humidity_pressure_summary(station_id, authorize?: false) do
      {:ok, summary} -> summary
      _ -> nil
    end
  end

  defp compute_summary(station_id, :wind) do
    case Voria2.Measurements.wind_summary(station_id, authorize?: false) do
      {:ok, summary} -> summary
      _ -> nil
    end
  end

  defp compute_summary(station_id, :rain) do
    case Voria2.Measurements.rain_summary(station_id, authorize?: false) do
      {:ok, summary} -> summary
      _ -> nil
    end
  end

  defp slug_to_summary_type(:scalar, "temperature"), do: :temperature
  defp slug_to_summary_type(:scalar, "humidity"), do: :humidity_pressure
  defp slug_to_summary_type(:scalar, "pressure"), do: :humidity_pressure
  defp slug_to_summary_type(:wind, _), do: :wind
  defp slug_to_summary_type(:rain, _), do: :rain
  defp slug_to_summary_type(_, _), do: nil

  defp store_with_ttl(key, value, ttl_ms) do
    expiry = System.monotonic_time(:millisecond) + ttl_ms
    :ets.insert(@table, {key, value, expiry})
  end

  defp lookup_with_ttl(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expiry}] ->
        now = System.monotonic_time(:millisecond)

        if now < expiry do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :expired_or_missing
        end

      [] ->
        :expired_or_missing
    end
  end
end
