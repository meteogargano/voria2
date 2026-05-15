defmodule Voria2Web.DailyLogControllerTest do
  use Voria2Web.ConnCase, async: false

  import Voria2.MeasurementsHelpers

  setup do
    previous_dailylog_in_local = Application.get_env(:voria2, :dailylog_in_local, false)
    previous_dailylog_wind_in_kmh = Application.get_env(:voria2, :dailylog_wind_in_kmh, false)
    Application.put_env(:voria2, :dailylog_in_local, false)
    Application.put_env(:voria2, :dailylog_wind_in_kmh, false)

    on_exit(fn ->
      Application.put_env(:voria2, :dailylog_in_local, previous_dailylog_in_local)
      Application.put_env(:voria2, :dailylog_wind_in_kmh, previous_dailylog_wind_in_kmh)
    end)

    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)

    temp_mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    hum_mt = create_measurement_type(slug: "humidity", storage_type: :scalar)
    pres_mt = create_measurement_type(slug: "pressure", storage_type: :scalar)
    wind_mt = create_measurement_type(slug: "wind", storage_type: :wind)
    rain_mt = create_measurement_type(slug: "rain", storage_type: :rain)

    temp_sensor = create_sensor_installation(station, temp_mt)
    hum_sensor = create_sensor_installation(station, hum_mt)
    pres_sensor = create_sensor_installation(station, pres_mt)
    wind_sensor = create_sensor_installation(station, wind_mt)
    rain_sensor = create_sensor_installation(station, rain_mt, rain_mode: :interval)

    %{
      station: station,
      installation: installation,
      temp_sensor: temp_sensor,
      hum_sensor: hum_sensor,
      pres_sensor: pres_sensor,
      wind_sensor: wind_sensor,
      rain_sensor: rain_sensor
    }
  end

  test "returns plaintext daily log with exact header and formatted values", %{
    conn: conn,
    station: station,
    temp_sensor: temp_sensor,
    hum_sensor: hum_sensor,
    pres_sensor: pres_sensor,
    wind_sensor: wind_sensor,
    rain_sensor: rain_sensor
  } do
    now = DateTime.utc_now()
    minute_1 = minute_today(now, 0, 0)
    minute_2 = minute_today(now, 0, 1)

    record_temperature!(temp_sensor, 30.0, minute_1)
    record_humidity!(hum_sensor, 70.0, minute_1)
    record_pressure!(pres_sensor, 1016.4, minute_1)
    record_wind!(wind_sensor, 3.0, -4.0, measured_at: minute_1, gust: 5.0)
    record_rain_interval!(rain_sensor, 1.2, minute_1)

    record_temperature!(temp_sensor, 8.7, minute_2)
    record_humidity!(hum_sensor, 90.0, minute_2)
    record_pressure!(pres_sensor, 1016.4, minute_2)
    record_wind!(wind_sensor, 0.0, -1.0, measured_at: minute_2)
    record_rain_interval!(rain_sensor, 0.0, minute_2)

    Voria2.Cache.invalidate_dailylog(station)

    conn = get(conn, "/dailylog/#{station.slug}")

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

    [header, row_1, row_2] = String.split(conn.resp_body, "\n")

    assert header ==
             "day month year hour minute temperature humidity dewpoint barometer windspeed gustspeed direction rainlastmin dailyrain monthlyrain yearlyrain heatindex"

    assert row_1 ==
             Enum.join(
               [
                 Integer.to_string(minute_1.day),
                 Integer.to_string(minute_1.month),
                 Integer.to_string(minute_1.year),
                 "0",
                 "0",
                 "30",
                 "70",
                 "23.93",
                 "1016.4",
                 "5",
                 "5",
                 "323",
                 "1.2",
                 "1.2",
                 "1.2",
                 "1.2",
                 "35.04"
               ],
               " "
             )

    assert row_2 ==
             Enum.join(
               [
                 Integer.to_string(minute_2.day),
                 Integer.to_string(minute_2.month),
                 Integer.to_string(minute_2.year),
                 "0",
                 "1",
                 "8.7",
                 "90",
                 "7.15",
                 "1016.4",
                 "1",
                 "ND",
                 "0",
                 "0",
                 "1.2",
                 "1.2",
                 "1.2",
                 "ND"
               ],
               " "
             )
  end

  test "returns 404 for unknown station slug", %{conn: conn} do
    conn = get(conn, "/dailylog/missing-station")
    assert response(conn, 404) == "Not found"
  end

  test "uses installation timezone when DAILYLOG_IN_LOCAL is enabled", %{
    conn: conn,
    station: station,
    installation: installation,
    temp_sensor: temp_sensor,
    hum_sensor: hum_sensor,
    pres_sensor: pres_sensor,
    wind_sensor: wind_sensor,
    rain_sensor: rain_sensor
  } do
    Application.put_env(:voria2, :dailylog_in_local, true)

    {:ok, _installation} =
      Voria2.Network.update_installation(installation, %{timezone: "Europe/Rome"},
        authorize?: false
      )

    {:ok, station} = Ash.load(station, [:installation], authorize?: false)

    now = DateTime.utc_now()
    {:ok, local_now} = DateTime.shift_zone(now, "Europe/Rome")
    local_date = DateTime.to_date(local_now)

    minute_local = DateTime.new!(local_date, ~T[00:30:00], "Europe/Rome")
    {:ok, minute_utc} = DateTime.shift_zone(minute_local, "Etc/UTC")

    previous_local = DateTime.add(minute_local, -60 * 60, :second)
    {:ok, previous_utc} = DateTime.shift_zone(previous_local, "Etc/UTC")

    record_temperature!(temp_sensor, 21.0, previous_utc)
    record_humidity!(hum_sensor, 55.0, previous_utc)
    record_pressure!(pres_sensor, 1009.0, previous_utc)
    record_wind!(wind_sensor, 1.0, 0.0, measured_at: previous_utc)
    record_rain_interval!(rain_sensor, 2.5, previous_utc)

    record_temperature!(temp_sensor, 22.0, minute_utc)
    record_humidity!(hum_sensor, 60.0, minute_utc)
    record_pressure!(pres_sensor, 1010.0, minute_utc)
    record_wind!(wind_sensor, 0.0, -1.0, measured_at: minute_utc)
    record_rain_interval!(rain_sensor, 0.5, minute_utc)

    Voria2.Cache.invalidate_dailylog(station, minute_utc)

    conn = get(conn, "/dailylog/#{station.slug}")
    lines = String.split(conn.resp_body, "\n")

    assert length(lines) == 2
    [_, row] = lines

    assert row ==
             Enum.join(
               [
                 Integer.to_string(local_date.day),
                 Integer.to_string(local_date.month),
                 Integer.to_string(local_date.year),
                 "0",
                 "30",
                 "22",
                 "60",
                 "13.88",
                 "1010",
                 "1",
                 "ND",
                 "0",
                 "0.5",
                 "0.5",
                 "3",
                 "3",
                 "ND"
               ],
               " "
             )
  end

  test "uses UTC by default even when installation has a timezone", %{
    conn: conn,
    station: station,
    installation: installation,
    temp_sensor: temp_sensor,
    hum_sensor: hum_sensor,
    pres_sensor: pres_sensor,
    wind_sensor: wind_sensor,
    rain_sensor: rain_sensor
  } do
    {:ok, _installation} =
      Voria2.Network.update_installation(installation, %{timezone: "Europe/Rome"},
        authorize?: false
      )

    {:ok, station} = Ash.load(station, [:installation], authorize?: false)

    measured_at = minute_today(DateTime.utc_now(), 22, 30)

    record_temperature!(temp_sensor, 18.0, measured_at)
    record_humidity!(hum_sensor, 50.0, measured_at)
    record_pressure!(pres_sensor, 1008.0, measured_at)
    record_wind!(wind_sensor, 0.0, -1.0, measured_at: measured_at)
    record_rain_interval!(rain_sensor, 0.4, measured_at)

    Voria2.Cache.invalidate_dailylog(station, measured_at)

    conn = get(conn, "/dailylog/#{station.slug}")
    lines = String.split(conn.resp_body, "\n")

    assert length(lines) == 2
    [_, row] = lines

    assert row ==
             Enum.join(
               [
                 Integer.to_string(measured_at.day),
                 Integer.to_string(measured_at.month),
                 Integer.to_string(measured_at.year),
                 "22",
                 "30",
                 "18",
                 "50",
                 "7.42",
                 "1008",
                 "1",
                 "ND",
                 "0",
                 "0.4",
                 "0.4",
                 "0.4",
                 "0.4",
                 "ND"
               ],
               " "
             )
  end

  test "converts wind values to km/h when DAILYLOG_WIND_IN_KMH is enabled", %{
    conn: conn,
    station: station,
    wind_sensor: wind_sensor
  } do
    Application.put_env(:voria2, :dailylog_wind_in_kmh, true)

    now = DateTime.utc_now()
    measured_at = minute_today(now, 0, 0)

    record_wind!(wind_sensor, 3.0, -4.0, measured_at: measured_at, gust: 5.0)

    Voria2.Cache.invalidate_dailylog(station, measured_at)

    conn = get(conn, "/dailylog/#{station.slug}")
    [header, row] = String.split(conn.resp_body, "\n")

    assert header ==
             "day month year hour minute temperature humidity dewpoint barometer windspeed gustspeed direction rainlastmin dailyrain monthlyrain yearlyrain heatindex"

    assert row ==
             Enum.join(
               [
                 Integer.to_string(measured_at.day),
                 Integer.to_string(measured_at.month),
                 Integer.to_string(measured_at.year),
                 "0",
                 "0",
                 "ND",
                 "ND",
                 "ND",
                 "ND",
                 "18",
                 "18",
                 "323",
                 "0",
                 "0",
                 "0",
                 "0",
                 "ND"
               ],
               " "
             )
  end

  defp minute_today(now, hour, minute) do
    day_start = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")
    DateTime.add(day_start, hour * 3600 + minute * 60, :second)
  end
end
