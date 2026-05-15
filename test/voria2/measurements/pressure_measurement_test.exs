defmodule Voria2.Measurements.PressureMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "pressure", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    %{sensor: sensor}
  end

  test "value=0.0 is invalid (must be > 0)", %{sensor: sensor} do
    assert {:error, %Ash.Error.Invalid{}} =
             Measurements.record_pressure(
               %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: 0.0},
               authorize?: false
             )
  end

  test "value=-1.0 is invalid", %{sensor: sensor} do
    assert {:error, %Ash.Error.Invalid{}} =
             Measurements.record_pressure(
               %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: -1.0},
               authorize?: false
             )
  end

  test "value=0.01 is valid (minimum positive)", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_pressure(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 0.01
               },
               authorize?: false
             )

    assert r.value == 0.01
  end

  test "value=1013.25 is valid (standard atmosphere)", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_pressure(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 1013.25
               },
               authorize?: false
             )

    assert r.value == 1013.25
  end

  test "value is rounded to 2 decimal places", %{sensor: sensor} do
    assert {:ok, r} =
             Measurements.record_pressure(
               %{
                 sensor_installation_id: sensor.id,
                 measured_at: DateTime.utc_now(),
                 value: 1006.9092026000001
               },
               authorize?: false
             )

    assert r.value == 1006.91
  end

  test "update rounds value to 2 decimal places", %{sensor: sensor} do
    {:ok, r} =
      Measurements.record_pressure(
        %{sensor_installation_id: sensor.id, measured_at: DateTime.utc_now(), value: 1013.25},
        authorize?: false
      )

    {:ok, r2} =
      Measurements.update_pressure(
        r,
        %{value: 1015.6789},
        authorize?: false
      )

    assert r2.value == 1015.68
  end
end
