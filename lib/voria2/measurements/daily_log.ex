defmodule Voria2.Measurements.DailyLog do
  @moduledoc false

  require Ash.Query

  alias Voria2.Measurements

  @header [
    "day",
    "month",
    "year",
    "hour",
    "minute",
    "temperature",
    "humidity",
    "dewpoint",
    "barometer",
    "windspeed",
    "gustspeed",
    "direction",
    "rainlastmin",
    "dailyrain",
    "monthlyrain",
    "yearlyrain",
    "heatindex"
  ]

  @dewpoint_a 17.625
  @dewpoint_b 243.04

  def render_for_station(station) do
    station = ensure_installation_loaded(station)
    context = time_context(station)
    wind_in_kmh? = dailylog_wind_in_kmh?()
    sensors = active_sensors(station.id)

    rain_sensor = Map.get(sensors, :rain)

    measurements = %{
      temperature:
        scalar_readings(Map.get(sensors, :temperature), context.day_from_utc, context.day_to_utc),
      humidity:
        scalar_readings(Map.get(sensors, :humidity), context.day_from_utc, context.day_to_utc),
      pressure:
        scalar_readings(Map.get(sensors, :pressure), context.day_from_utc, context.day_to_utc),
      wind: wind_readings(Map.get(sensors, :wind), context.day_from_utc, context.day_to_utc),
      day_rain: rain_readings(rain_sensor, context.day_from_utc, context.day_to_utc)
    }

    {month_rain_before, year_rain_before} =
      if rain_sensor do
        {
          rain_total_before(rain_sensor, context.month_from_utc, context.day_from_utc),
          rain_total_before(rain_sensor, context.year_from_utc, context.day_from_utc)
        }
      else
        {0.0, 0.0}
      end

    daily_lines =
      minute_rows(
        context,
        measurements,
        not is_nil(rain_sensor),
        wind_in_kmh?,
        month_rain_before,
        year_rain_before
      )
      |> Enum.map(&render_row/1)

    Enum.join([Enum.join(@header, " ") | daily_lines], "\n")
  end

  def cache_scope_for_station(station, measured_at \\ nil) do
    station = ensure_installation_loaded(station)
    local? = Application.get_env(:voria2, :dailylog_in_local, false)
    timezone = station.installation && station.installation.timezone

    case resolve_timezone(timezone, local?) do
      {:ok, tz} ->
        base_dt = measured_at || DateTime.utc_now()

        case DateTime.shift_zone(base_dt, tz) do
          {:ok, local_dt} -> {{:local, tz}, DateTime.to_date(local_dt)}
          _ -> {:utc, DateTime.to_date(base_dt)}
        end

      :error ->
        base_dt = measured_at || DateTime.utc_now()
        {:utc, DateTime.to_date(base_dt)}
    end
  end

  def invalidate_keys_for_station(station, measured_at \\ nil) do
    station = ensure_installation_loaded(station)
    current = cache_scope_for_station(station)
    relevant = cache_scope_for_station(station, measured_at)

    [current, relevant]
    |> Enum.uniq()
  end

  defp minute_rows(
         context,
         measurements,
         has_rain_sensor?,
         wind_in_kmh?,
         month_rain_before,
         year_rain_before
       ) do
    temp_by_minute = map_by_minute(measurements.temperature)
    hum_by_minute = map_by_minute(measurements.humidity)
    pres_by_minute = map_by_minute(measurements.pressure)
    wind_by_minute = map_by_minute(measurements.wind)

    rain_day_by_minute = map_by_minute(measurements.day_rain)

    minute_keys =
      [
        Map.keys(temp_by_minute),
        Map.keys(hum_by_minute),
        Map.keys(pres_by_minute),
        Map.keys(wind_by_minute),
        Map.keys(rain_day_by_minute)
      ]
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort(&(DateTime.compare(&1, &2) != :gt))

    {_day_total, rows} =
      Enum.reduce(
        minute_keys,
        {0.0, []},
        fn minute_dt, {running_day_rain, rows} ->
          temp = value_of(Map.get(temp_by_minute, minute_dt))
          humidity = value_of(Map.get(hum_by_minute, minute_dt))
          pressure = value_of(Map.get(pres_by_minute, minute_dt))
          wind = Map.get(wind_by_minute, minute_dt)
          day_rain = Map.get(rain_day_by_minute, minute_dt)

          rain_last_min =
            cond do
              has_rain_sensor? and day_rain -> day_rain.interval_mm
              has_rain_sensor? -> 0.0
              true -> nil
            end

          next_running_day_rain = running_day_rain + (rain_last_min || 0.0)

          dewpoint = compute_dewpoint(temp, humidity)
          heatindex = compute_heatindex(temp, humidity)

          windspeed =
            if wind do
              wind_speed(wind.u, wind.v)
              |> maybe_convert_wind_speed(wind_in_kmh?)
            end

          gustspeed = if wind, do: maybe_convert_wind_speed(wind.gust, wind_in_kmh?)

          direction =
            if wind do
              wind.u
              |> direction_deg(wind.v)
              |> round()
            end

          row = %{
            day: context.parts_by_minute[minute_dt].day,
            month: context.parts_by_minute[minute_dt].month,
            year: context.parts_by_minute[minute_dt].year,
            hour: context.parts_by_minute[minute_dt].hour,
            minute: context.parts_by_minute[minute_dt].minute,
            temperature: temp,
            humidity: humidity,
            dewpoint: dewpoint,
            barometer: pressure,
            windspeed: windspeed,
            gustspeed: gustspeed,
            direction: direction,
            rainlastmin: rain_last_min,
            dailyrain: if(has_rain_sensor?, do: next_running_day_rain, else: nil),
            monthlyrain:
              if(has_rain_sensor?, do: month_rain_before + next_running_day_rain, else: nil),
            yearlyrain:
              if(has_rain_sensor?, do: year_rain_before + next_running_day_rain, else: nil),
            heatindex: heatindex
          }

          {next_running_day_rain, [row | rows]}
        end
      )

    Enum.reverse(rows)
  end

  defp time_context(station) do
    now_utc = DateTime.utc_now()
    local? = Application.get_env(:voria2, :dailylog_in_local, false)
    timezone = station.installation && station.installation.timezone

    case resolve_timezone(timezone, local?) do
      {:ok, tz} ->
        {:ok, local_now} = DateTime.shift_zone(now_utc, tz)
        local_date = DateTime.to_date(local_now)

        day_from_local = DateTime.new!(local_date, ~T[00:00:00], tz)
        day_to_local = DateTime.new!(Date.add(local_date, 1), ~T[00:00:00], tz)

        month_from_local =
          DateTime.new!(
            %Date{year: local_date.year, month: local_date.month, day: 1},
            ~T[00:00:00],
            tz
          )

        year_from_local =
          DateTime.new!(%Date{year: local_date.year, month: 1, day: 1}, ~T[00:00:00], tz)

        %{
          day_from_utc: shift_to_utc!(day_from_local),
          day_to_utc: shift_to_utc!(day_to_local),
          month_from_utc: shift_to_utc!(month_from_local),
          year_from_utc: shift_to_utc!(year_from_local),
          parts_by_minute: local_parts_by_minute(day_from_local, day_to_local)
        }

      :error ->
        day_date = DateTime.to_date(now_utc)
        day_from_utc = DateTime.new!(day_date, ~T[00:00:00], "Etc/UTC")
        day_to_utc = DateTime.add(day_from_utc, 86_400, :second)

        month_from_utc =
          DateTime.new!(
            %Date{year: day_date.year, month: day_date.month, day: 1},
            ~T[00:00:00],
            "Etc/UTC"
          )

        year_from_utc =
          DateTime.new!(%Date{year: day_date.year, month: 1, day: 1}, ~T[00:00:00], "Etc/UTC")

        %{
          day_from_utc: day_from_utc,
          day_to_utc: day_to_utc,
          month_from_utc: month_from_utc,
          year_from_utc: year_from_utc,
          parts_by_minute: utc_parts_by_minute(day_from_utc, day_to_utc)
        }
    end
  end

  defp local_parts_by_minute(day_from_local, day_to_local) do
    build_parts_map(day_from_local, day_to_local, fn local_dt ->
      {:ok, utc_dt} = DateTime.shift_zone(local_dt, "Etc/UTC")
      {minute_key(utc_dt), date_parts(local_dt)}
    end)
  end

  defp utc_parts_by_minute(day_from_utc, day_to_utc) do
    build_parts_map(day_from_utc, day_to_utc, fn utc_dt ->
      {minute_key(utc_dt), date_parts(utc_dt)}
    end)
  end

  defp build_parts_map(start_dt, end_dt, mapper) do
    Stream.unfold(start_dt, fn current_dt ->
      if DateTime.compare(current_dt, end_dt) == :lt do
        next_dt = DateTime.add(current_dt, 60, :second)
        {mapper.(current_dt), next_dt}
      end
    end)
    |> Map.new()
  end

  defp resolve_timezone(timezone, true) when is_binary(timezone) and timezone != "" do
    case DateTime.now(timezone) do
      {:ok, _} -> {:ok, timezone}
      _ -> :error
    end
  end

  defp resolve_timezone(_, _), do: :error

  defp shift_to_utc!(datetime) do
    case DateTime.shift_zone(datetime, "Etc/UTC") do
      {:ok, utc_dt} -> utc_dt
      {:error, reason} -> raise "failed to shift datetime to UTC: #{inspect(reason)}"
    end
  end

  defp active_sensors(station_id) do
    Voria2.Measurements.SensorInstallation
    |> Ash.Query.filter(station_id == ^station_id)
    |> Ash.Query.load(:measurement_type)
    |> Ash.read!(authorize?: false)
    |> Enum.reject(& &1.removed_at)
    |> Enum.reduce(%{}, fn sensor, acc ->
      key = sensor_key(sensor)

      if is_nil(key) or Map.has_key?(acc, key) do
        acc
      else
        Map.put(acc, key, sensor)
      end
    end)
  end

  defp sensor_key(sensor) do
    case {sensor.measurement_type.storage_type, sensor.measurement_type.slug} do
      {:scalar, "temperature"} -> :temperature
      {:scalar, "humidity"} -> :humidity
      {:scalar, "pressure"} -> :pressure
      {:wind, _} -> :wind
      {:rain, _} -> :rain
      _ -> nil
    end
  end

  defp scalar_readings(nil, _from, _to), do: []

  defp scalar_readings(sensor, from, to) do
    case sensor.measurement_type.slug do
      "temperature" ->
        Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)

      "humidity" ->
        Measurements.humidity_for_sensor!(sensor.id, from, to, authorize?: false)

      "pressure" ->
        Measurements.pressure_for_sensor!(sensor.id, from, to, authorize?: false)
    end
  end

  defp wind_readings(nil, _from, _to), do: []

  defp wind_readings(sensor, from, to),
    do: Measurements.wind_for_sensor!(sensor.id, from, to, authorize?: false)

  defp rain_readings(nil, _from, _to), do: []

  defp rain_readings(sensor, from, to),
    do: Measurements.rain_for_sensor!(sensor.id, from, to, authorize?: false)

  defp map_by_minute(readings) do
    Enum.reduce(readings, %{}, fn reading, acc ->
      Map.put(acc, minute_key(reading.measured_at), reading)
    end)
  end

  defp rain_total_before(sensor, from, day_from) do
    import Ecto.Query

    Voria2.Repo.one(
      from r in Voria2.Measurements.RainMeasurement,
        where:
          r.sensor_installation_id == ^sensor.id and
            r.measured_at >= ^from and r.measured_at < ^day_from,
        select: sum(r.interval_mm)
    ) || 0.0
  end

  defp minute_key(datetime) do
    %{datetime | second: 0, microsecond: {0, 0}}
  end

  defp date_parts(datetime) do
    %{
      day: datetime.day,
      month: datetime.month,
      year: datetime.year,
      hour: datetime.hour,
      minute: datetime.minute
    }
  end

  defp value_of(nil), do: nil
  defp value_of(%{value: value}), do: value

  defp compute_dewpoint(nil, _humidity), do: nil
  defp compute_dewpoint(_temp, nil), do: nil
  defp compute_dewpoint(_temp, humidity) when humidity <= 0, do: nil

  defp compute_dewpoint(temp_c, humidity) do
    g = :math.log(humidity / 100.0) + @dewpoint_a * temp_c / (@dewpoint_b + temp_c)
    @dewpoint_b * g / (@dewpoint_a - g)
  end

  defp compute_heatindex(nil, _humidity), do: nil
  defp compute_heatindex(_temp, nil), do: nil

  defp compute_heatindex(temp_c, humidity) do
    temp_f = temp_c * 9.0 / 5.0 + 32.0

    if temp_f < 80.0 or humidity < 40.0 do
      nil
    else
      heat_index_f =
        -42.379 + 2.049_015_23 * temp_f + 10.143_331_27 * humidity -
          0.224_755_41 * temp_f * humidity - 0.006_837_83 * temp_f * temp_f -
          0.054_817_17 * humidity * humidity + 0.001_228_74 * temp_f * temp_f * humidity +
          0.000_852_82 * temp_f * humidity * humidity -
          0.000_001_99 * temp_f * temp_f * humidity * humidity

      adjusted_f =
        cond do
          humidity < 13.0 and temp_f >= 80.0 and temp_f <= 112.0 ->
            heat_index_f -
              (13.0 - humidity) / 4.0 * :math.sqrt((17.0 - abs(temp_f - 95.0)) / 17.0)

          humidity > 85.0 and temp_f >= 80.0 and temp_f <= 87.0 ->
            heat_index_f + (humidity - 85.0) / 10.0 * ((87.0 - temp_f) / 5.0)

          true ->
            heat_index_f
        end

      (adjusted_f - 32.0) * 5.0 / 9.0
    end
  end

  defp dailylog_wind_in_kmh?, do: Application.get_env(:voria2, :dailylog_wind_in_kmh, false)

  defp maybe_convert_wind_speed(nil, _convert?), do: nil
  defp maybe_convert_wind_speed(speed, false), do: speed
  defp maybe_convert_wind_speed(speed, true), do: speed * 3.6

  defp wind_speed(u, v), do: :math.sqrt(u * u + v * v)

  defp direction_deg(u, v) do
    deg = :math.atan2(u, v) * 180.0 / :math.pi()
    mod(deg + 180.0, 360.0)
  end

  defp mod(a, b) do
    r = :math.fmod(a, b)
    if r < 0, do: r + b, else: r
  end

  defp render_row(row) do
    [
      row.day,
      row.month,
      row.year,
      row.hour,
      row.minute,
      render_value(row.temperature),
      render_value(row.humidity),
      render_value(row.dewpoint),
      render_value(row.barometer),
      render_value(row.windspeed),
      render_value(row.gustspeed),
      render_value(row.direction),
      render_value(row.rainlastmin),
      render_value(row.dailyrain),
      render_value(row.monthlyrain),
      render_value(row.yearlyrain),
      render_value(row.heatindex)
    ]
    |> Enum.join(" ")
  end

  defp render_value(nil), do: "ND"
  defp render_value(value) when is_integer(value), do: Integer.to_string(value)

  defp render_value(value) when is_float(value) do
    value
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp ensure_installation_loaded(%{installation: installation} = station)
       when not is_struct(installation, Ash.NotLoaded),
       do: station

  defp ensure_installation_loaded(station) do
    {:ok, loaded_station} = Ash.load(station, [:installation], authorize?: false)
    loaded_station
  end
end
