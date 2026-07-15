defmodule Voria2.Measurements.RainMeasurementTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "rain", storage_type: :rain)
    sensor = create_sensor_installation(station, mt, rain_mode: :interval)
    %{sensor: sensor}
  end

  describe "record_interval" do
    test "stores interval_mm directly", %{sensor: sensor} do
      assert {:ok, r} =
               Measurements.record_rain_interval(
                 %{
                   sensor_installation_id: sensor.id,
                   measured_at: DateTime.utc_now(),
                   interval_mm: 3.7
                 },
                 authorize?: false
               )

      assert r.interval_mm == 3.7
    end

    test "interval_mm is rounded to 2 decimal places", %{sensor: sensor} do
      assert {:ok, r} =
               Measurements.record_rain_interval(
                 %{
                   sensor_installation_id: sensor.id,
                   measured_at: DateTime.utc_now(),
                   interval_mm: 3.456789
                 },
                 authorize?: false
               )

      assert r.interval_mm == 3.46
    end

    test "update rounds interval_mm to 2 decimal places", %{sensor: sensor} do
      {:ok, r} =
        Measurements.record_rain_interval(
          %{
            sensor_installation_id: sensor.id,
            measured_at: DateTime.utc_now(),
            interval_mm: 5.0
          },
          authorize?: false
        )

      {:ok, r2} =
        Measurements.update_rain(
          r,
          %{interval_mm: 7.890123},
          authorize?: false
        )

      assert r2.interval_mm == 7.89
    end

    test "negative interval_mm is invalid", %{sensor: sensor} do
      assert {:error, %Ash.Error.Invalid{}} =
               Measurements.record_rain_interval(
                 %{
                   sensor_installation_id: sensor.id,
                   measured_at: DateTime.utc_now(),
                   interval_mm: -0.1
                 },
                 authorize?: false
               )
    end
  end

  describe "record_cumulative" do
    setup do
      user = create_user()
      installation = create_installation(user)
      station = create_station(installation)
      mt = create_measurement_type(slug: "rain-cum", storage_type: :rain)
      sensor = create_sensor_installation(station, mt, rain_mode: :cumulative)
      %{cum_sensor: sensor}
    end

    test "cumulative sequence computes correct interval_mm", %{cum_sensor: sensor} do
      now = DateTime.utc_now()
      sid = sensor.id

      # 1. first reading of 0.0 — state is NOT initialised (0.0 is skipped to
      #    avoid locking in a spurious baseline; state stays nil)
      r1 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -5, :second),
            cumulative_value: 0.0
          },
          authorize?: false
        )

      assert r1.interval_mm == 0.0

      # 2. first non-zero reading (5.0) — establishes baseline; interval=0.0
      #    because there is still no prior state to diff against
      r2 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -4, :second),
            cumulative_value: 5.0
          },
          authorize?: false
        )

      assert r2.interval_mm == 0.0

      # 3. cumulative=5.0 → interval=0.0 (no change)
      r3 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -3, :second),
            cumulative_value: 5.0
          },
          authorize?: false
        )

      assert r3.interval_mm == 0.0

      # 4. cumulative=8.5 → interval=3.5
      r4 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -2, :second),
            cumulative_value: 8.5
          },
          authorize?: false
        )

      assert r4.interval_mm == 3.5

      # 5. cumulative=2.0 (reset, diff<0) → interval=0.0
      r5 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -1, :second),
            cumulative_value: 2.0
          },
          authorize?: false
        )

      assert r5.interval_mm == 0.0
    end

    test "console reset to 0 preserves state; first reading after reset loses its interval", %{
      cum_sensor: sensor
    } do
      now = DateTime.utc_now()
      sid = sensor.id

      # establish a baseline at 25.0
      Measurements.record_rain_cumulative!(
        %{
          sensor_installation_id: sid,
          measured_at: DateTime.add(now, -3, :second),
          cumulative_value: 25.0
        },
        authorize?: false
      )

      # console resets → 0.0 is skipped, state stays at 25.0
      r_reset =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -2, :second),
            cumulative_value: 0.0
          },
          authorize?: false
        )

      assert r_reset.interval_mm == 0.0

      {:ok, state} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert state.last_cumulative_value == 25.0

      # first reading after reset: diff negative (2.0 - 25.0) → clamped to 0;
      # state re-initialises at 2.0; the 2mm since reset is not captured
      r_first =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -1, :second),
            cumulative_value: 2.0
          },
          authorize?: false
        )

      assert r_first.interval_mm == 0.0

      {:ok, state2} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert state2.last_cumulative_value == 2.0

      # subsequent readings work correctly
      r_next =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sid, measured_at: now, cumulative_value: 5.0},
          authorize?: false
        )

      assert r_next.interval_mm == 3.0
    end

    test "RainCumulativeState is upserted correctly", %{cum_sensor: sensor} do
      now = DateTime.utc_now()

      Measurements.record_rain_cumulative!(
        %{sensor_installation_id: sensor.id, measured_at: now, cumulative_value: 10.0},
        authorize?: false
      )

      assert {:ok, state} = Measurements.get_rain_cumulative_state(sensor.id, authorize?: false)
      assert state.last_cumulative_value == 10.0
    end

    # ── San Nicandro pattern: spurious 0 interleaved with real data ──────────
    # API alternates between returning the real cumulative (552.2) and 0 from
    # a different sensor. The 0 must never corrupt the state.
    test "spurious 0 between real readings does not corrupt state", %{cum_sensor: sensor} do
      now = DateTime.utc_now()
      sid = sensor.id

      # baseline
      r1 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -3, :second),
            cumulative_value: 552.2
          },
          authorize?: false
        )

      assert r1.interval_mm == 0.0

      {:ok, state1} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert state1.last_cumulative_value == 552.2

      # spurious 0 — state must remain 552.2, not be reset
      r2 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -2, :second),
            cumulative_value: 0.0
          },
          authorize?: false
        )

      assert r2.interval_mm == 0.0

      {:ok, state2} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert state2.last_cumulative_value == 552.2

      # real reading again — diff = 552.2 - 552.2 = 0, NOT 552.2
      r3 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -1, :second),
            cumulative_value: 552.2
          },
          authorize?: false
        )

      assert r3.interval_mm == 0.0

      # actual rain: small increment
      r4 =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sid, measured_at: now, cumulative_value: 552.4},
          authorize?: false
        )

      assert_in_delta r4.interval_mm, 0.2, 1.0e-9
    end

    # ── Multiple consecutive 0s before any real reading ───────────────────────
    # State must stay nil throughout; first non-zero establishes the baseline.
    test "multiple consecutive 0s before first non-zero leave state nil", %{cum_sensor: sensor} do
      now = DateTime.utc_now()
      sid = sensor.id

      for i <- 1..3 do
        r =
          Measurements.record_rain_cumulative!(
            %{
              sensor_installation_id: sid,
              measured_at: DateTime.add(now, -i, :second),
              cumulative_value: 0.0
            },
            authorize?: false
          )

        assert r.interval_mm == 0.0
      end

      # state must still be nil — no row created
      assert {:ok, nil} =
               Measurements.get_rain_cumulative_state(sid,
                 authorize?: false,
                 not_found_error?: false
               )

      # first non-zero establishes baseline with interval=0
      r =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sid, measured_at: now, cumulative_value: 5.0},
          authorize?: false
        )

      assert r.interval_mm == 0.0

      {:ok, state} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert state.last_cumulative_value == 5.0
    end

    # ── Mid-year baseline (rain_year_mm scenario) ─────────────────────────────
    # First-ever reading is a large non-zero value (year-to-date total).
    # Must establish baseline with interval=0, not report all historical rain.
    test "large first reading establishes baseline, subsequent delta is correct", %{
      cum_sensor: sensor
    } do
      now = DateTime.utc_now()
      sid = sensor.id

      r1 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -2, :second),
            cumulative_value: 552.2
          },
          authorize?: false
        )

      assert r1.interval_mm == 0.0

      # 2.5 mm of rain since baseline
      r2 =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -1, :second),
            cumulative_value: 554.7
          },
          authorize?: false
        )

      assert_in_delta r2.interval_mm, 2.5, 1.0e-9

      # no change
      r3 =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sid, measured_at: now, cumulative_value: 554.7},
          authorize?: false
        )

      assert r3.interval_mm == 0.0
    end

    # ── Two sensors are fully independent ────────────────────────────────────
    test "cumulative state is isolated per sensor", %{cum_sensor: sensor} do
      user = create_user()
      installation = create_installation(user)
      station2 = create_station(installation)
      mt2 = create_measurement_type(slug: "rain-cum-b", storage_type: :rain)
      sensor2 = create_sensor_installation(station2, mt2, rain_mode: :cumulative)

      now = DateTime.utc_now()

      # sensor1 baseline at 100
      Measurements.record_rain_cumulative!(
        %{
          sensor_installation_id: sensor.id,
          measured_at: DateTime.add(now, -1, :second),
          cumulative_value: 100.0
        },
        authorize?: false
      )

      # sensor2 baseline at 200
      Measurements.record_rain_cumulative!(
        %{
          sensor_installation_id: sensor2.id,
          measured_at: DateTime.add(now, -1, :second),
          cumulative_value: 200.0
        },
        authorize?: false
      )

      # sensor1 gets 5mm more
      r1 =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sensor.id, measured_at: now, cumulative_value: 105.0},
          authorize?: false
        )

      assert r1.interval_mm == 5.0

      # sensor2 gets 3mm more — must not be affected by sensor1's state
      r2 =
        Measurements.record_rain_cumulative!(
          %{sensor_installation_id: sensor2.id, measured_at: now, cumulative_value: 203.0},
          authorize?: false
        )

      assert r2.interval_mm == 3.0
    end

    test "interval_mm is rounded to 2 decimal places in cumulative mode", %{cum_sensor: sensor} do
      now = DateTime.utc_now()
      sid = sensor.id

      # baseline
      Measurements.record_rain_cumulative!(
        %{
          sensor_installation_id: sid,
          measured_at: DateTime.add(now, -2, :second),
          cumulative_value: 10.0
        },
        authorize?: false
      )

      # 3.456789 mm more -> should be rounded to 3.46
      r =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: DateTime.add(now, -1, :second),
            cumulative_value: 13.456789
          },
          authorize?: false
        )

      assert r.interval_mm == 3.46
    end

    test "duplicate cumulative replay reuses stored interval without mutating state", %{
      cum_sensor: sensor
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      sid = sensor.id

      Measurements.record_rain_cumulative!(
        %{
          sensor_installation_id: sid,
          measured_at: DateTime.add(now, -2, :second),
          cumulative_value: 10.0
        },
        authorize?: false
      )

      first =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: now,
            cumulative_value: 13.5
          },
          authorize?: false
        )

      assert first.interval_mm == 3.5

      {:ok, before_state} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      before_updated_at = before_state.last_updated_at

      replay =
        Measurements.record_rain_cumulative!(
          %{
            sensor_installation_id: sid,
            measured_at: now,
            cumulative_value: 13.5
          },
          authorize?: false
        )

      assert replay.id == first.id
      assert replay.interval_mm == 3.5

      {:ok, after_state} = Measurements.get_rain_cumulative_state(sid, authorize?: false)
      assert after_state.last_cumulative_value == 13.5
      assert after_state.last_updated_at == before_updated_at
    end
  end
end
