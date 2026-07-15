defmodule Voria2.Ingest do
  alias Voria2.Measurements

  @required ["sensor", "timestamp"]

  def dispatch(station, params) do
    with :ok <- validate_required(params, @required),
         {:ok, timestamp} <- parse_timestamp(params["timestamp"]),
         {:ok, sensor} <- find_sensor(station.id, params["sensor"]) do
      try do
        do_dispatch(sensor, params, timestamp)
      rescue
        error in Ash.Error.Invalid -> {:error, error}
      end
    end
  end

  defp find_sensor(station_id, slug) do
    case Voria2.Cache.sensor_for_station_slug(station_id, slug) do
      {:ok, nil} -> {:error, {:unknown_sensor, slug}}
      {:ok, sensor} -> {:ok, sensor}
    end
  end

  defp do_dispatch(sensor, params, timestamp) do
    result =
      case sensor.measurement_type.storage_type do
        :scalar -> dispatch_scalar(sensor, params, timestamp)
        :wind -> dispatch_wind(sensor, params, timestamp)
        :rain -> dispatch_rain(sensor, params, timestamp)
        :custom -> dispatch_custom(sensor, params, timestamp)
      end

    if result == :ok do
      Voria2.Cache.broadcast_measurement(sensor.station_id, sensor, timestamp)
      Voria2.Cache.touch_station(sensor.station_id)
      Voria2.Network.FaultClearer.clear_station(sensor.station_id)
    end

    result
  end

  defp dispatch_scalar(sensor, params, ts) do
    case Map.fetch(params, "value") do
      {:ok, v} when is_number(v) ->
        record_fn = scalar_record_fn(sensor.measurement_type.slug)

        apply(Measurements, record_fn, [
          %{sensor_installation_id: sensor.id, measured_at: ts, value: v},
          [authorize?: false]
        ])
        |> persist_result()

      _ ->
        {:error, {:invalid_field, "value", "must be a number"}}
    end
  end

  defp scalar_record_fn("humidity"), do: :record_humidity
  defp scalar_record_fn("pressure"), do: :record_pressure
  defp scalar_record_fn(_), do: :record_temperature

  defp dispatch_wind(sensor, params, ts) do
    with {:ok, u} <- require_number(params, "u"),
         {:ok, v} <- require_number(params, "v") do
      gust = if is_number(params["gust"]), do: params["gust"], else: nil

      Measurements.record_wind(
        %{sensor_installation_id: sensor.id, measured_at: ts, u: u, v: v, gust: gust},
        authorize?: false
      )
      |> persist_result()
    end
  end

  defp dispatch_rain(sensor, params, ts) do
    case sensor.rain_mode do
      :cumulative ->
        if is_number(params["cumulative_mm"]) do
          Measurements.record_rain_cumulative(
            %{
              sensor_installation_id: sensor.id,
              measured_at: ts,
              cumulative_value: params["cumulative_mm"]
            },
            authorize?: false
          )
          |> persist_result()
        else
          {:error, {:invalid_field, "cumulative_mm", "must be a number"}}
        end

      :interval ->
        if is_number(params["interval_mm"]) do
          Measurements.record_rain_interval(
            %{
              sensor_installation_id: sensor.id,
              measured_at: ts,
              interval_mm: params["interval_mm"]
            },
            authorize?: false
          )
          |> persist_result()
        else
          {:error, {:invalid_field, "interval_mm", "must be a number"}}
        end

      nil ->
        # rain_mode not set — fall back to field detection
        cond do
          is_number(params["interval_mm"]) ->
            Measurements.record_rain_interval(
              %{
                sensor_installation_id: sensor.id,
                measured_at: ts,
                interval_mm: params["interval_mm"]
              },
              authorize?: false
            )
            |> persist_result()

          is_number(params["cumulative_mm"]) ->
            Measurements.record_rain_cumulative(
              %{
                sensor_installation_id: sensor.id,
                measured_at: ts,
                cumulative_value: params["cumulative_mm"]
              },
              authorize?: false
            )
            |> persist_result()

          true ->
            {:error,
             {:invalid_field, "interval_mm|cumulative_mm", "one of these must be a number"}}
        end
    end
  end

  defp dispatch_custom(sensor, params, ts) do
    Measurements.record_custom_measurement(
      %{
        sensor_installation_id: sensor.id,
        measurement_type_id: sensor.measurement_type_id,
        measured_at: ts,
        value: params["value"],
        raw: params["raw"]
      },
      authorize?: false
    )
    |> persist_result()
  end

  defp parse_timestamp(nil), do: {:error, {:invalid_field, "timestamp", "missing"}}

  defp parse_timestamp(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, {:invalid_field, "timestamp", "invalid ISO8601"}}
    end
  end

  defp parse_timestamp(_), do: {:error, {:invalid_field, "timestamp", "must be a string"}}

  defp validate_required(params, keys) do
    missing = Enum.filter(keys, fn k -> is_nil(params[k]) end)
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp require_number(params, key) do
    case params[key] do
      v when is_number(v) -> {:ok, v}
      nil -> {:error, {:invalid_field, key, "missing"}}
      _ -> {:error, {:invalid_field, key, "must be a number"}}
    end
  end

  defp persist_result({:ok, _record}), do: :ok
  defp persist_result({:error, reason}), do: {:error, reason}
end
