defmodule Voria2.Measurements.CustomMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "soil-moisture", storage_type: :custom)
    sensor = create_sensor_installation(station, mt)
    %{sensor: sensor, mt: mt}
  end

  test "record with float value is stored", %{sensor: sensor, mt: mt} do
    assert {:ok, r} =
             Measurements.record_custom_measurement(
               %{
                 sensor_installation_id: sensor.id,
                 measurement_type_id: mt.id,
                 measured_at: DateTime.utc_now(),
                 value: 42.5
               },
               authorize?: false
             )

    assert r.value == 42.5
    assert is_nil(r.raw)
  end

  test "value is rounded to 2 decimal places", %{sensor: sensor, mt: mt} do
    assert {:ok, r} =
             Measurements.record_custom_measurement(
               %{
                 sensor_installation_id: sensor.id,
                 measurement_type_id: mt.id,
                 measured_at: DateTime.utc_now(),
                 value: 78.901234
               },
               authorize?: false
             )

    assert r.value == 78.9
  end

  test "update rounds value to 2 decimal places", %{sensor: sensor, mt: mt} do
    {:ok, r} =
      Measurements.record_custom_measurement(
        %{
          sensor_installation_id: sensor.id,
          measurement_type_id: mt.id,
          measured_at: DateTime.utc_now(),
          value: 50.0
        },
        authorize?: false
      )

    {:ok, r2} =
      Measurements.update_custom(
        r,
        %{value: 67.890123},
        authorize?: false
      )

    assert r2.value == 67.89
  end

  test "record with raw map is stored", %{sensor: sensor, mt: mt} do
    raw_data = %{"voltage" => 3.3, "raw_adc" => 1024}

    assert {:ok, r} =
             Measurements.record_custom_measurement(
               %{
                 sensor_installation_id: sensor.id,
                 measurement_type_id: mt.id,
                 measured_at: DateTime.utc_now(),
                 raw: raw_data
               },
               authorize?: false
             )

    assert r.raw == raw_data
    assert is_nil(r.value)
  end

  test "for_sensor returns readings in time range", %{sensor: sensor, mt: mt} do
    now = DateTime.utc_now()
    t1 = DateTime.add(now, -200, :second)
    t2 = DateTime.add(now, -100, :second)

    Measurements.record_custom_measurement!(
      %{
        sensor_installation_id: sensor.id,
        measurement_type_id: mt.id,
        measured_at: t1,
        value: 1.0
      },
      authorize?: false
    )

    Measurements.record_custom_measurement!(
      %{
        sensor_installation_id: sensor.id,
        measurement_type_id: mt.id,
        measured_at: t2,
        value: 2.0
      },
      authorize?: false
    )

    from = DateTime.add(now, -150, :second)

    assert {:ok, readings} =
             Measurements.custom_for_sensor(sensor.id, from, now, authorize?: false)

    assert length(readings) == 1
    assert hd(readings).value == 2.0
  end
end
