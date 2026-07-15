defmodule Voria2.Measurements.TemperatureMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    %{user: user, sensor: sensor}
  end

  test "record stores value correctly", %{sensor: sensor} do
    at = DateTime.utc_now()

    assert {:ok, r} =
             Measurements.record_temperature(
               %{sensor_installation_id: sensor.id, measured_at: at, value: 22.5},
               authorize?: false
             )

    assert r.value == 22.5
    assert r.sensor_installation_id == sensor.id
  end

  test "value is rounded to 2 decimal places", %{sensor: sensor} do
    at = DateTime.utc_now()

    {:ok, r} =
      Measurements.record_temperature(
        %{sensor_installation_id: sensor.id, measured_at: at, value: 10.055555555555555},
        authorize?: false
      )

    assert r.value == 10.06
  end

  test "update rounds value to 2 decimal places", %{sensor: sensor} do
    {:ok, r} =
      Measurements.record_temperature(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.utc_now(),
          value: 1008.0605752
        },
        authorize?: false
      )

    assert r.value == 1008.06

    {:ok, r2} =
      Measurements.update_temperature(
        r,
        %{value: 1012.34567},
        authorize?: false
      )

    assert r2.value == 1012.35
  end

  test "for_sensor filters by sensor and time range", %{sensor: sensor} do
    now = DateTime.utc_now()
    t1 = DateTime.add(now, -300, :second)
    t2 = DateTime.add(now, -200, :second)
    t3 = DateTime.add(now, -100, :second)

    record_temperature!(sensor, 10.0, t1)
    record_temperature!(sensor, 15.0, t2)
    record_temperature!(sensor, 20.0, t3)

    from = DateTime.add(now, -250, :second)
    to = now

    assert {:ok, readings} =
             Measurements.temperature_for_sensor(sensor.id, from, to, authorize?: false)

    assert length(readings) == 2
    assert Enum.map(readings, & &1.value) == [15.0, 20.0]
  end

  test "for_sensor returns ascending by measured_at", %{sensor: sensor} do
    now = DateTime.utc_now()
    t1 = DateTime.add(now, -200, :second)
    t2 = DateTime.add(now, -100, :second)

    record_temperature!(sensor, 20.0, t2)
    record_temperature!(sensor, 10.0, t1)

    from = DateTime.add(now, -300, :second)

    assert {:ok, [r1, r2]} =
             Measurements.temperature_for_sensor(sensor.id, from, now, authorize?: false)

    assert r1.value == 10.0
    assert r2.value == 20.0
  end

  test "policy: other user's sensor is forbidden" do
    other = create_user()
    other_installation = create_installation(other)
    other_station = create_station(other_installation)
    mt = create_measurement_type()
    other_sensor = create_sensor_installation(other_station, mt)

    record_temperature!(other_sensor, 25.0)

    user = create_user()
    now = DateTime.utc_now()
    from = DateTime.add(now, -3600, :second)

    assert {:ok, []} =
             Measurements.temperature_for_sensor(other_sensor.id, from, now, actor: user)
  end

  test "record is idempotent for sensor_installation_id + measured_at", %{sensor: sensor} do
    at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, first} =
             Measurements.record_temperature(
               %{sensor_installation_id: sensor.id, measured_at: at, value: 22.5},
               authorize?: false
             )

    assert {:ok, second} =
             Measurements.record_temperature(
               %{sensor_installation_id: sensor.id, measured_at: at, value: 23.75},
               authorize?: false
             )

    assert first.id == second.id

    assert {:ok, [reading]} =
             Measurements.temperature_for_sensor(
               sensor.id,
               DateTime.add(at, -1, :second),
               DateTime.add(at, 1, :second),
               authorize?: false
             )

    assert reading.value == 23.75
  end
end
