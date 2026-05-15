defmodule Voria2.Measurements.HumidityMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "humidity", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    %{sensor: sensor}
  end

  test "value=0.0 is valid", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_humidity(
               %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: 0.0},
               authorize?: false
             )

    assert r.value == 0.0
  end

  test "value=100.0 is valid", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_humidity(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 100.0
               },
               authorize?: false
             )

    assert r.value == 100.0
  end

  test "value=73.5 is valid (typical mid-range)", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_humidity(
               %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: 73.5},
               authorize?: false
             )

    assert r.value == 73.5
  end

  test "value is rounded to 2 decimal places", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_humidity(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 45.6789
               },
               authorize?: false
             )

    assert r.value == 45.68
  end

  test "update rounds value to 2 decimal places", %{sensor: sensor} do
    {:ok, r} =
      Measurements.record_humidity(
        %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: 50.0},
        authorize?: false
      )

    {:ok, r2} =
      Measurements.update_humidity(
        r,
        %{value: 55.1234},
        authorize?: false
      )

    assert r2.value == 55.12
  end

  test "value=-0.1 is invalid", %{sensor: sensor} do
    assert {:error, %Ash.Error.Invalid{}} =
             Measurements.record_humidity(
               %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: -0.1},
               authorize?: false
             )
  end

  test "value=100.1 is invalid", %{sensor: sensor} do
    assert {:error, %Ash.Error.Invalid{}} =
             Measurements.record_humidity(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 100.1
               },
               authorize?: false
             )
  end
end
