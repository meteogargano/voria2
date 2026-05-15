defmodule Voria2.Measurements.WindMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "wind", storage_type: :wind)
    sensor = create_sensor_installation(station, mt)
    %{sensor: sensor}
  end

  defp record_and_load!(sensor, u, v, opts \\ []) do
    now = Keyword.get(opts, :measured_at, DateTime.utc_now())
    gust = Keyword.get(opts, :gust)

    r =
      Measurements.record_wind!(
        %{sensor_installation_id: sensor.id, measured_at: now, u: u, v: v, gust: gust},
        authorize?: false
      )

    from = DateTime.add(now, -1, :second)
    to = DateTime.add(now, 1, :second)

    [loaded] =
      Measurements.wind_for_sensor!(sensor.id, from, to,
        load: [:speed, :direction_deg],
        authorize?: false
      )

    loaded
  end

  # Cardinal direction tests (u/v convention: u=eastward positive=from-west, v=northward positive=from-south)

  test "northerly wind: u=0, v=-1 → speed=1.0, direction=0°", %{sensor: sensor} do
    r = record_and_load!(sensor, 0.0, -1.0)
    assert_in_delta r.speed, 1.0, 0.001
    assert_in_delta r.direction_deg, 0.0, 0.001
  end

  test "easterly wind: u=-1, v=0 → speed=1.0, direction=90°", %{sensor: sensor} do
    r = record_and_load!(sensor, -1.0, 0.0)
    assert_in_delta r.speed, 1.0, 0.001
    assert_in_delta r.direction_deg, 90.0, 0.001
  end

  test "southerly wind: u=0, v=1 → speed=1.0, direction=180°", %{sensor: sensor} do
    r = record_and_load!(sensor, 0.0, 1.0)
    assert_in_delta r.speed, 1.0, 0.001
    assert_in_delta r.direction_deg, 180.0, 0.001
  end

  test "westerly wind: u=1, v=0 → speed=1.0, direction=270°", %{sensor: sensor} do
    r = record_and_load!(sensor, 1.0, 0.0)
    assert_in_delta r.speed, 1.0, 0.001
    assert_in_delta r.direction_deg, 270.0, 0.001
  end

  test "Pythagorean triple: u=3, v=4 → speed=5.0", %{sensor: sensor} do
    r = record_and_load!(sensor, 3.0, 4.0)
    assert_in_delta r.speed, 5.0, 0.001
  end

  test "Pythagorean triple: u=3, v=-4 → speed=5.0, direction≈323.1° (NNW)", %{sensor: sensor} do
    r = record_and_load!(sensor, 3.0, -4.0)
    assert_in_delta r.speed, 5.0, 0.001
    # atan2(3, -4) = π - atan(3/4) ≈ 143.13°; +180 mod 360 = 323.13°
    assert_in_delta r.direction_deg, 323.13, 0.05
  end

  test "gust=nil stored as nil", %{sensor: sensor} do
    r =
      Measurements.record_wind!(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.utc_now(),
          u: 1.0,
          v: 0.0,
          gust: nil
        },
        authorize?: false
      )

    assert is_nil(r.gust)
  end

  test "gust=12.5 stored as 12.5", %{sensor: sensor} do
    r =
      Measurements.record_wind!(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.utc_now(),
          u: 1.0,
          v: 0.0,
          gust: 12.5
        },
        authorize?: false
      )

    assert r.gust == 12.5
  end

  test "wind components are rounded to 2 decimal places", %{sensor: sensor} do
    r =
      Measurements.record_wind!(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.utc_now(),
          u: 3.14159,
          v: 2.71828,
          gust: 12.3456
        },
        authorize?: false
      )

    assert r.u == 3.14
    assert r.v == 2.72
    assert r.gust == 12.35
  end

  test "update rounds wind components to 2 decimal places", %{sensor: sensor} do
    r =
      Measurements.record_wind!(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.utc_now(),
          u: 1.0,
          v: 2.0,
          gust: 10.0
        },
        authorize?: false
      )

    {:ok, r2} =
      Measurements.update_wind(
        r,
        %{u: 4.5678, v: 5.6789, gust: 15.1234},
        authorize?: false
      )

    assert r2.u == 4.57
    assert r2.v == 5.68
    assert r2.gust == 15.12
  end
end
