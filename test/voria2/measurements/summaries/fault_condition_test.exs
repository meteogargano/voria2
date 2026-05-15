defmodule Voria2.Measurements.Summaries.FaultConditionTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers
  alias Voria2.Measurements

  defp at_offset(base, seconds), do: DateTime.add(base, seconds, :second)
  defp today_start, do: DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

  defp create_temp_station do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    {user, station, sensor}
  end

  defp create_rain_station do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "rain", storage_type: :rain)
    sensor = create_sensor_installation(station, mt, rain_mode: :interval)
    {user, station, sensor}
  end

  defp create_wind_station do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "wind", storage_type: :wind)
    sensor = create_sensor_installation(station, mt)
    {user, station, sensor}
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 1: Station Offline — Default 1h Window Returns Nil/Empty
  # ─────────────────────────────────────────────────────────────────────────────

  describe "station offline: default 1h window returns nil/empty" do
    test "temperature: no data in default 1h window → current nil, history []" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 18.0, at_offset(at, -5 * 3600))
      record_temperature!(sensor, 19.0, at_offset(at, -4 * 3600))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.current)
      assert summary.history == []
      assert summary.trend == :stable
    end

    test "rain: no data in default window → instant_rain 0.0 (not stale)" do
      {user, station, sensor} = create_rain_station()
      at = DateTime.utc_now()
      record_rain_interval!(sensor, 3.5, at_offset(at, -4 * 3600))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: at}, actor: user)
      # Window is [T-1h, T]: empty. List.last([]) = nil → instant_rain = 0.0, not stale 3.5
      assert summary.instant_rain == 0.0
    end

    test "wind: no data in default window → all current values nil, wind_rose []" do
      {user, station, sensor} = create_wind_station()
      at = DateTime.utc_now()
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -5 * 3600))
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -4 * 3600))

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.current_speed)
      assert summary.wind_rose == []
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 2: Station Offline — Wide Window Returns Stale Pre-Outage Data
  # ─────────────────────────────────────────────────────────────────────────────

  describe "station offline: wide window returns stale pre-outage data" do
    test "temperature: current is last pre-outage value (stale, not nil)" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 18.0, at_offset(at, -5 * 3600))
      record_temperature!(sensor, 19.0, at_offset(at, -4 * 3600))
      record_temperature!(sensor, 20.0, at_offset(at, -3 * 3600))

      assert {:ok, summary} =
               Measurements.temperature_summary(station.id, %{at: at, offset_seconds: -21600},
                 actor: user
               )

      assert summary.current == 20.0
    end

    test "temperature: trend is stale pre-outage slope (cannot update during outage)" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 18.0, at_offset(at, -5 * 3600))
      record_temperature!(sensor, 19.0, at_offset(at, -4 * 3600))
      record_temperature!(sensor, 20.0, at_offset(at, -3 * 3600))

      assert {:ok, summary} =
               Measurements.temperature_summary(station.id, %{at: at, offset_seconds: -21600},
                 actor: user
               )

      assert summary.trend == :rising
      assert length(summary.history) == 3
      # Last history entry is the T-3h reading or earlier — confirms no post-outage update
      assert DateTime.compare(List.last(summary.history).t, at_offset(at, -3 * 3600)) != :gt
    end

    test "rain: instant_rain is stale pre-outage value when window covers pre-outage data" do
      {user, station, sensor} = create_rain_station()
      at = DateTime.utc_now()
      record_rain_interval!(sensor, 3.5, at_offset(at, -4 * 3600))

      assert {:ok, summary} =
               Measurements.rain_summary(station.id, %{at: at, offset_seconds: -21600},
                 actor: user
               )

      # Wide window includes the T-4h reading; it is the last in the window → stale instant_rain
      # Contrast with Group 1 test: narrow window = empty = 0.0; wide window = stale = 3.5
      assert_in_delta summary.instant_rain, 3.5, 0.001
    end

    test "wind: current_direction reflects last pre-outage reading" do
      {user, station, sensor} = create_wind_station()
      at = DateTime.utc_now()
      # North wind at T-5h
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -5 * 3600))
      # South wind at T-3h (last pre-outage reading)
      record_wind!(sensor, 0.0, 1.0, measured_at: at_offset(at, -3 * 3600))

      assert {:ok, summary} =
               Measurements.wind_summary(station.id, %{at: at, offset_seconds: -21600},
                 actor: user
               )

      # direction_deg(0.0, 1.0) = mod(atan2(0,1)*180/pi + 180, 360) = mod(0 + 180, 360) = 180° (South)
      assert_in_delta summary.current_direction, 180.0, 0.01
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 3: Three-Hour Gap, Station Resumes
  # ─────────────────────────────────────────────────────────────────────────────

  describe "three-hour gap, station resumes" do
    test "diff_24h still works when data exists exactly at T-24h" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 12.0, at_offset(at, -86400))
      record_temperature!(sensor, 17.0, at_offset(at, -30 * 60))

      # Default 1h window covers T-30min reading; diff_24h uses its own ±30min search independently
      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert_in_delta summary.diff_24h, 5.0, 0.001
    end

    test "diff_24h is nil when outage spans the 24h-ago search window" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      # Last reading before gap: T-25h (before ±30min of T-24h)
      record_temperature!(sensor, 10.0, at_offset(at, -25 * 3600))
      # Readings resume after gap
      record_temperature!(sensor, 15.0, at_offset(at, -10 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      # Search range is [T-24h30min, T-23h30min]; T-25h is before this range → not found
      assert is_nil(summary.diff_24h)
    end

    test "rain_rate severely underestimated when 3h gap falls in last-10 window" do
      {user, station, sensor} = create_rain_station()
      at = DateTime.utc_now()

      # 5 readings T-4h to T-3h at 15-min intervals (1.0mm each)
      for i <- 0..4 do
        record_rain_interval!(sensor, 1.0, at_offset(at, -(4 * 3600) + i * 15 * 60))
      end

      # 5 readings T-5min to T-1min at 1-min intervals (1.0mm each)
      for i <- 0..4 do
        record_rain_interval!(sensor, 1.0, at_offset(at, -(5 - i) * 60))
      end

      assert {:ok, summary} =
               Measurements.rain_summary(station.id, %{at: at, offset_seconds: -(5 * 3600)},
                 actor: user
               )

      # avg_gap includes the 3h inter-reading gap; dilutes the true 1mm/min post-gap intensity
      # Without gap: ~60mm/h; inflated avg_gap ≈ 1593s → ~2.3mm/h
      assert summary.rain_rate < 12.0
      assert summary.rain_rate > 0.0
    end

    test "trend recalculates correctly from first 3 post-resume readings" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()

      # Pre-gap: falling trend
      record_temperature!(sensor, 25.0, at_offset(at, -4 * 3600))
      record_temperature!(sensor, 24.0, at_offset(at, -(3 * 3600 + 30 * 60)))
      record_temperature!(sensor, 23.0, at_offset(at, -3 * 3600))

      # Post-gap: rising trend
      record_temperature!(sensor, 15.0, at_offset(at, -5 * 60))
      record_temperature!(sensor, 16.0, at_offset(at, -4 * 60))
      record_temperature!(sensor, 17.0, at_offset(at, -3 * 60))

      assert {:ok, summary} =
               Measurements.temperature_summary(
                 station.id,
                 %{at: at, offset_seconds: -(5 * 3600)},
                 actor: user
               )

      # Enum.take(readings, -3) = last 3 in-window readings = post-gap rising values
      assert summary.trend == :rising
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 4: Rain-Specific Gap Behaviors
  # ─────────────────────────────────────────────────────────────────────────────

  describe "rain: gap-specific behaviors" do
    test "days_without_rain: complete offline day is indistinguishable from dry day" do
      {user, station, sensor} = create_rain_station()
      now = DateTime.utc_now()
      ts = today_start()
      # Rain exactly 5 days ago at 01:00; no readings for days -4 through today (offline)
      record_rain_interval!(sensor, 2.0, DateTime.add(ts, -(5 * 86400) + 3600, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      # Known limitation: offline days inflate days_without_rain by N. No data = counted as dry.
      assert summary.days_without_rain == 5
    end

    test "days_without_rain stops correctly when rain fell before outage" do
      {user, station, sensor} = create_rain_station()
      now = DateTime.utc_now()
      ts = today_start()
      # Rain 2 days ago at 01:00; today and yesterday offline
      record_rain_interval!(sensor, 2.0, DateTime.add(ts, -(2 * 86400) + 3600, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      # today (dry) + yesterday (dry) = 2; 2-days-ago has rain → stop
      assert summary.days_without_rain == 2
    end

    test "total_today includes readings from both sides of intra-day gap" do
      {user, station, sensor} = create_rain_station()
      now = DateTime.utc_now()
      ts = today_start()

      # 5 readings this morning: 2.0mm each at 30-min intervals from midnight+1min
      for i <- 0..4 do
        record_rain_interval!(sensor, 2.0, DateTime.add(ts, 60 + i * 30 * 60, :second))
      end

      # Gap from ~morning to T-30min, then 1 reading at T-30min
      record_rain_interval!(sensor, 1.5, DateTime.add(now, -30 * 60, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      # total_today queries [midnight, now] regardless of offset_seconds; gap contributes 0
      assert_in_delta summary.total_today, 11.5, 0.001
    end

    test "rain_rate drops to 0 when only 1 reading in window after long outage" do
      {user, station, sensor} = create_rain_station()
      at = DateTime.utc_now()
      record_rain_interval!(sensor, 3.0, at_offset(at, -4 * 3600))

      # Default 1h window: empty → rain_rate = 0.0
      assert {:ok, summary1} = Measurements.rain_summary(station.id, %{at: at}, actor: user)
      assert summary1.rain_rate == 0.0

      # Wide window with only 1 reading: n < 2 guard → 0.0
      assert {:ok, summary2} =
               Measurements.rain_summary(station.id, %{at: at, offset_seconds: -21600},
                 actor: user
               )

      assert summary2.rain_rate == 0.0
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 5: diff_24h Edge Cases
  # ─────────────────────────────────────────────────────────────────────────────

  describe "diff_24h edge cases" do
    test "no reading within ±30min of T-24h → nil" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      # T-25h is before the search range [T-24h30min, T-23h30min]
      record_temperature!(sensor, 10.0, at_offset(at, -25 * 3600))
      record_temperature!(sensor, 14.0, at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.diff_24h)
    end

    test "reading exactly at T-24h → correct delta" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 10.0, at_offset(at, -86400))
      record_temperature!(sensor, 14.0, at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert_in_delta summary.diff_24h, 4.0, 0.001
    end

    test "reading at T-24h29min (inside window) → found" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()

      # 86400 + 29*60 = 88140s ago; search_from = 88200s ago → 88140 > 88200 is false, so it is inside
      record_temperature!(sensor, 8.0, at_offset(at, -(86400 + 29 * 60)))
      record_temperature!(sensor, 11.0, at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert_in_delta summary.diff_24h, 3.0, 0.001
    end

    test "reading at T-24h31min (outside window) → nil" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      # 86400 + 31*60 = 88260s ago; search_from = 88200s ago → 88260 > 88200, outside window
      record_temperature!(sensor, 8.0, at_offset(at, -(86400 + 31 * 60)))
      record_temperature!(sensor, 11.0, at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.diff_24h)
    end

    test "two readings near T-24h: find_closest picks the nearer one" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      # T-24h20min = 88200s ago (20 min from T-24h)
      record_temperature!(sensor, 10.0, at_offset(at, -(86400 + 20 * 60)))
      # T-24h10min = 87000s ago (10 min from T-24h) — closer
      record_temperature!(sensor, 12.0, at_offset(at, -(86400 + 10 * 60)))
      record_temperature!(sensor, 15.0, at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      # diff_24h = 15.0 - 12.0 = 3.0 (uses T-24h10min, the closer reading)
      assert_in_delta summary.diff_24h, 3.0, 0.001
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 6: Large Dataset Tests
  # ─────────────────────────────────────────────────────────────────────────────

  describe "large dataset tests" do
    @tag :slow
    test "7 days × every-5-min temperature with 3h gap: min/max and history length" do
      {user, station, sensor} = create_temp_station()
      now = DateTime.utc_now()

      # 2016 readings (288/day × 7 days), sinusoidal values in [15, 25]
      # Skip indices 864..899 (3h block ~3 days ago) to simulate an outage
      Enum.each(0..(2016 - 1), fn i ->
        unless i >= 864 and i < 900 do
          t = DateTime.add(now, -(i * 300), :second)
          value = 20.0 + :math.sin(i * :math.pi() / 144) * 5.0
          record_temperature!(sensor, value, t)
        end
      end)

      assert {:ok, summary} =
               Measurements.temperature_summary(
                 station.id,
                 %{at: now, offset_seconds: -(7 * 86400)},
                 actor: user
               )

      assert summary.min_today != nil
      assert summary.max_today != nil
      # All values are in [15, 25] by construction
      assert summary.min_today.value >= 15.0
      assert summary.max_today.value <= 25.0
    end

    @tag :slow
    test "outage spanning rest of today: max_today frozen at last pre-outage reading" do
      {user, station, sensor} = create_temp_station()
      now = DateTime.utc_now()
      ts = today_start()
      outage_start = at_offset(now, -4 * 3600)

      # Insert readings at 1h, 2h, 3h after midnight — only if they're before the outage
      Enum.each([{1, 15.0}, {2, 17.0}, {3, 19.0}], fn {hours, value} ->
        t = DateTime.add(ts, hours * 3600, :second)

        if DateTime.compare(t, outage_start) == :lt do
          record_temperature!(sensor, value, t)
        end
      end)

      assert {:ok, summary} =
               Measurements.temperature_summary(
                 station.id,
                 %{at: now, offset_seconds: -(24 * 3600)},
                 actor: user
               )

      # If readings were inserted, max_today must be at or before the outage start
      if summary.max_today != nil do
        assert DateTime.compare(summary.max_today.at, outage_start) != :gt
      end
    end

    @tag :slow
    test "30 days of rain: days_without_rain counts from last actual rain day" do
      {user, station, sensor} = create_rain_station()
      now = DateTime.utc_now()
      ts = today_start()

      # Rain 25 days ago at 01:00 (stops the dry-day counter)
      record_rain_interval!(sensor, 5.0, DateTime.add(ts, -(25 * 86400) + 3600, :second))

      # Zero-mm readings on 5 days between the rain and today
      # 0mm total = dry (total > 0 check), so these do NOT stop the counter
      for days_ago <- [5, 10, 15, 20, 22] do
        record_rain_interval!(sensor, 0.0, DateTime.add(ts, -(days_ago * 86400) + 3600, :second))
      end

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert summary.days_without_rain == 25
    end

    @tag :slow
    test "48h wind data: wind_rose percentages proportional to direction distribution" do
      {user, station, sensor} = create_wind_station()
      now = DateTime.utc_now()

      # 288 readings every 10 min over 48h
      # i=0 (newest) .. i=287 (oldest): newest 96 = South, oldest 192 = North
      Enum.each(0..287, fn i ->
        t = DateTime.add(now, -(i * 600), :second)
        # i < 96 → South {u=0, v=1}; i >= 96 → North {u=0, v=-1}
        {u, v} = if i < 96, do: {0.0, 1.0}, else: {0.0, -1.0}
        record_wind!(sensor, u, v, measured_at: t)
      end)

      assert {:ok, summary} =
               Measurements.wind_summary(station.id, %{at: now, offset_seconds: -(48 * 3600)},
                 actor: user
               )

      wind_rose = summary.wind_rose
      n_entry = Enum.find(wind_rose, &(&1.sector == "N"))
      s_entry = Enum.find(wind_rose, &(&1.sector == "S"))

      assert n_entry != nil
      assert s_entry != nil
      # 192 North / 288 total = 66.67%; 96 South / 288 = 33.33%
      assert_in_delta n_entry.pct, 66.67, 0.5
      assert_in_delta s_entry.pct, 33.33, 0.5
      assert length(wind_rose) == 2
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group 7: Sensor Decommissioned Mid-Day
  # ─────────────────────────────────────────────────────────────────────────────

  describe "sensor decommissioned mid-day" do
    test "decommissioned temperature sensor: summary returns nil/empty struct" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 20.0, at_offset(at, -50 * 60))
      record_temperature!(sensor, 21.0, at_offset(at, -40 * 60))
      record_temperature!(sensor, 22.0, at_offset(at, -30 * 60))

      Measurements.decommission_sensor(sensor, authorize?: false)

      assert {:ok, summary} =
               Measurements.temperature_summary(station.id, %{at: DateTime.utc_now()},
                 actor: user
               )

      assert is_nil(summary.current)
      assert summary.history == []
      assert summary.trend == :stable
    end

    test "decommissioned rain sensor: returns zero defaults (not error, not nil struct)" do
      {user, station, sensor} = create_rain_station()
      at = DateTime.utc_now()
      record_rain_interval!(sensor, 2.0, at_offset(at, -50 * 60))
      record_rain_interval!(sensor, 1.5, at_offset(at, -40 * 60))
      record_rain_interval!(sensor, 1.0, at_offset(at, -30 * 60))

      Measurements.decommission_sensor(sensor, authorize?: false)

      assert {:ok, summary} =
               Measurements.rain_summary(station.id, %{at: DateTime.utc_now()}, actor: user)

      assert summary.total_today == 0.0
      assert summary.instant_rain == 0.0
      assert summary.rain_rate == 0.0
      assert summary.days_without_rain == 0
    end

    test "decommissioned wind sensor: all current values nil, wind_rose []" do
      {user, station, sensor} = create_wind_station()
      at = DateTime.utc_now()
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -50 * 60))
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -30 * 60))

      Measurements.decommission_sensor(sensor, authorize?: false)

      assert {:ok, summary} =
               Measurements.wind_summary(station.id, %{at: DateTime.utc_now()}, actor: user)

      assert is_nil(summary.current_speed)
      assert is_nil(summary.current_direction)
      assert summary.wind_rose == []
    end

    test "readings remain in DB after decommission but are unreachable via summary" do
      {user, station, sensor} = create_temp_station()
      at = DateTime.utc_now()
      record_temperature!(sensor, 20.0, at_offset(at, -50 * 60))
      record_temperature!(sensor, 21.0, at_offset(at, -40 * 60))
      record_temperature!(sensor, 22.0, at_offset(at, -30 * 60))

      Measurements.decommission_sensor(sensor, authorize?: false)

      # Direct DB query still returns all 3 readings (data persists after decommission)
      readings =
        Measurements.temperature_for_sensor!(sensor.id, at_offset(at, -3600), at,
          authorize?: false
        )

      assert length(readings) == 3

      # Summary excludes the sensor because find_active_sensor filters removed_at IS NULL
      assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.current)
    end
  end
end
