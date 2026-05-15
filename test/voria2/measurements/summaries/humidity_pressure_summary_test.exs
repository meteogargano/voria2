defmodule Voria2.Measurements.Summaries.HumidityPressureSummaryTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)

    hum_mt = create_measurement_type(slug: "humidity", storage_type: :scalar)
    pres_mt = create_measurement_type(slug: "pressure", storage_type: :scalar)
    temp_mt = create_measurement_type(slug: "temperature", storage_type: :scalar)

    hum_sensor = create_sensor_installation(station, hum_mt)
    pres_sensor = create_sensor_installation(station, pres_mt)
    temp_sensor = create_sensor_installation(station, temp_mt)

    %{
      user: user,
      station: station,
      hum_sensor: hum_sensor,
      pres_sensor: pres_sensor,
      temp_sensor: temp_sensor,
      hum_mt: hum_mt,
      pres_mt: pres_mt
    }
  end

  defp at_offset(base, seconds), do: DateTime.add(base, seconds, :second)

  test "dewpoint T=20°C, RH=50% → ≈9.27°C", %{
    user: user,
    station: station,
    hum_sensor: hum,
    pres_sensor: pres,
    temp_sensor: temp
  } do
    at = DateTime.utc_now()
    t = at_offset(at, -30 * 60)

    record_temperature!(temp, 20.0, t)
    record_humidity!(hum, 50.0, t)
    record_pressure!(pres, 1013.0, t)

    assert {:ok, summary} =
             Measurements.humidity_pressure_summary(station.id, %{at: at}, actor: user)

    assert_in_delta summary.dewpoint, 9.27, 0.05
  end

  test "dewpoint T=25°C, RH=80% → ≈21.30°C", %{
    user: user,
    station: station,
    hum_sensor: hum,
    pres_sensor: pres,
    temp_sensor: temp
  } do
    at = DateTime.utc_now()
    t = at_offset(at, -30 * 60)

    record_temperature!(temp, 25.0, t)
    record_humidity!(hum, 80.0, t)
    record_pressure!(pres, 1013.0, t)

    assert {:ok, summary} =
             Measurements.humidity_pressure_summary(station.id, %{at: at}, actor: user)

    assert_in_delta summary.dewpoint, 21.30, 0.05
  end

  test "dewpoint T=15°C, RH=100% → ≈15.0°C (saturated)", %{
    user: user,
    station: station,
    hum_sensor: hum,
    pres_sensor: pres,
    temp_sensor: temp
  } do
    at = DateTime.utc_now()
    t = at_offset(at, -30 * 60)

    record_temperature!(temp, 15.0, t)
    record_humidity!(hum, 100.0, t)
    record_pressure!(pres, 1013.0, t)

    assert {:ok, summary} =
             Measurements.humidity_pressure_summary(station.id, %{at: at}, actor: user)

    assert_in_delta summary.dewpoint, 15.0, 0.05
  end

  test "no temperature sensor → dewpoint is nil", %{
    user: _user,
    station: _station,
    hum_mt: hum_mt,
    pres_mt: pres_mt
  } do
    # Build a separate station without a temperature sensor; reuse existing mts
    user2 = create_user()
    inst2 = create_installation(user2)
    station2 = create_station(inst2)
    hum2 = create_sensor_installation(station2, hum_mt)
    pres2 = create_sensor_installation(station2, pres_mt)

    at = DateTime.utc_now()
    t = at_offset(at, -30 * 60)
    record_humidity!(hum2, 60.0, t)
    record_pressure!(pres2, 1013.0, t)

    assert {:ok, summary} =
             Measurements.humidity_pressure_summary(station2.id, %{at: at}, actor: user2)

    assert is_nil(summary.dewpoint)
  end

  test "no humidity sensor → error", %{user: _user, station: _station, pres_mt: pres_mt} do
    # Station2 has only a pressure sensor (no humidity)
    user2 = create_user()
    inst2 = create_installation(user2)
    station2 = create_station(inst2)
    _pres2 = create_sensor_installation(station2, pres_mt)

    assert {:error, _} = Measurements.humidity_pressure_summary(station2.id, actor: user2)
  end

  test "no pressure sensor → error", %{user: _user, station: _station, hum_mt: hum_mt} do
    # Station2 has only a humidity sensor (no pressure)
    user2 = create_user()
    inst2 = create_installation(user2)
    station2 = create_station(inst2)
    _hum2 = create_sensor_installation(station2, hum_mt)

    assert {:error, _} = Measurements.humidity_pressure_summary(station2.id, actor: user2)
  end

  test "barometer_trend equals pressure_trend", %{
    user: user,
    station: station,
    hum_sensor: hum,
    pres_sensor: pres
  } do
    at = DateTime.utc_now()
    record_humidity!(hum, 50.0, at_offset(at, -50 * 60))
    record_humidity!(hum, 51.0, at_offset(at, -40 * 60))
    record_humidity!(hum, 52.0, at_offset(at, -30 * 60))
    record_pressure!(pres, 1010.0, at_offset(at, -50 * 60))
    record_pressure!(pres, 1012.0, at_offset(at, -40 * 60))
    record_pressure!(pres, 1014.0, at_offset(at, -30 * 60))

    assert {:ok, summary} =
             Measurements.humidity_pressure_summary(station.id, %{at: at}, actor: user)

    assert summary.barometer_trend == summary.pressure_trend
  end
end
