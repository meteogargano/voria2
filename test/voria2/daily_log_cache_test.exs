defmodule Voria2.DailyLogCacheTest do
  use Voria2.DataCase, async: false

  import Voria2.MeasurementsHelpers

  setup do
    start_supervised!({Voria2.CacheInvalidationListener, []})

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
    temp_sensor = create_sensor_installation(station, temp_mt)

    %{station: station, installation: installation, temp_sensor: temp_sensor}
  end

  test "get_or_compute_dailylog stores body in ETS", %{station: station, temp_sensor: temp_sensor} do
    record_temperature!(temp_sensor, 12.3, DateTime.utc_now())
    Voria2.Cache.invalidate_dailylog(station)

    {:ok, body} = Voria2.Cache.get_or_compute_dailylog(station)
    {scope, date} = Voria2.Measurements.DailyLog.cache_scope_for_station(station)

    assert [{_, ^body, _expiry}] =
             :ets.lookup(:voria2_cache, {:dailylog, station.id, scope, date})

    assert body =~ "day month year hour minute"
  end

  test "returns cached dailylog on second call", %{station: station, temp_sensor: temp_sensor} do
    record_temperature!(temp_sensor, 13.4, DateTime.utc_now())
    Voria2.Cache.invalidate_dailylog(station)

    {:ok, _body} = Voria2.Cache.get_or_compute_dailylog(station)
    {scope, date} = Voria2.Measurements.DailyLog.cache_scope_for_station(station)

    sentinel = "sentinel body"

    :ets.insert(
      :voria2_cache,
      {{:dailylog, station.id, scope, date}, sentinel,
       System.monotonic_time(:millisecond) + 300_000}
    )

    assert {:ok, ^sentinel} = Voria2.Cache.get_or_compute_dailylog(station)
  end

  test "measurement broadcast warms dailylog cache", %{station: station, temp_sensor: temp_sensor} do
    measured_at = DateTime.utc_now()
    record_temperature!(temp_sensor, 14.5, measured_at)
    Voria2.Cache.invalidate_dailylog(station, measured_at)

    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      "measurements",
      {:new_measurement,
       %{
         station_id: station.id,
         sensor_id: temp_sensor.id,
         summary_type: :temperature,
         measured_at: measured_at
       }}
    )

    Process.sleep(200)

    {scope, date} = Voria2.Measurements.DailyLog.cache_scope_for_station(station, measured_at)

    assert [{_, value, _expiry}] =
             :ets.lookup(:voria2_cache, {:dailylog, station.id, scope, date})

    assert value =~ "14.5"
  end

  test "local timezone cache scope uses local date when enabled", %{
    station: station,
    installation: installation
  } do
    Application.put_env(:voria2, :dailylog_in_local, true)

    {:ok, _installation} =
      Voria2.Network.update_installation(installation, %{timezone: "Europe/Rome"},
        authorize?: false
      )

    {:ok, station} = Ash.load(station, [:installation], authorize?: false)
    measured_at = ~U[2026-05-05 22:30:00Z]

    assert {{:local, "Europe/Rome"}, ~D[2026-05-06]} =
             Voria2.Measurements.DailyLog.cache_scope_for_station(station, measured_at)
  end

  test "cache scope defaults to UTC when local flag is disabled", %{
    station: station,
    installation: installation
  } do
    {:ok, _installation} =
      Voria2.Network.update_installation(installation, %{timezone: "Europe/Rome"},
        authorize?: false
      )

    {:ok, station} = Ash.load(station, [:installation], authorize?: false)
    measured_at = ~U[2026-05-05 22:30:00Z]

    assert {:utc, ~D[2026-05-05]} =
             Voria2.Measurements.DailyLog.cache_scope_for_station(station, measured_at)
  end
end
