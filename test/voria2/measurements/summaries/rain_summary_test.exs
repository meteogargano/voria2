defmodule Voria2.Measurements.Summaries.RainSummaryTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "rain", storage_type: :rain)
    sensor = create_sensor_installation(station, mt, rain_mode: :interval)
    %{user: user, station: station, sensor: sensor}
  end

  defp today_start, do: DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

  test "total_today: sum of interval_mm since midnight, yesterday excluded", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    now = DateTime.utc_now()
    ts = today_start()

    # Yesterday readings (should not count)
    yesterday = DateTime.add(ts, -3600, :second)
    record_rain_interval!(sensor, 99.0, yesterday)

    # Today readings
    record_rain_interval!(sensor, 3.0, DateTime.add(ts, 60, :second))
    record_rain_interval!(sensor, 2.5, DateTime.add(ts, 3600, :second))
    record_rain_interval!(sensor, 1.0, DateTime.add(now, -10 * 60, :second))

    assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
    assert_in_delta summary.total_today, 6.5, 0.001
  end

  test "instant_rain: most recent reading's interval_mm", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    now = DateTime.utc_now()
    record_rain_interval!(sensor, 2.0, DateTime.add(now, -60 * 60, :second))
    record_rain_interval!(sensor, 5.5, DateTime.add(now, -30 * 60, :second))

    assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
    assert_in_delta summary.instant_rain, 5.5, 0.001
  end

  describe "rain_rate" do
    test "5 readings of 1.0mm at 30-min intervals → 2.0 mm/h", %{
      user: user,
      station: station,
      sensor: sensor
    } do
      now = DateTime.utc_now()
      # 5 readings spaced 30 min apart, all 1.0mm
      for i <- 4..0//-1 do
        record_rain_interval!(sensor, 1.0, DateTime.add(now, -(i * 30 * 60), :second))
      end

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert_in_delta summary.rain_rate, 2.0, 0.01
    end

    test "single reading → 0.0 mm/h (insufficient data)", %{
      user: user,
      station: station,
      sensor: sensor
    } do
      now = DateTime.utc_now()
      record_rain_interval!(sensor, 5.0, DateTime.add(now, -30 * 60, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert summary.rain_rate == 0.0
    end

    test "no readings → 0.0 mm/h", %{user: user, station: station} do
      now = DateTime.utc_now()
      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert summary.rain_rate == 0.0
    end
  end

  describe "days_without_rain" do
    test "today has rain → 0", %{user: user, station: station, sensor: sensor} do
      now = DateTime.utc_now()
      record_rain_interval!(sensor, 2.0, DateTime.add(now, -10 * 60, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert summary.days_without_rain == 0
    end

    test "3 consecutive zero days → 3", %{user: user, station: station, sensor: sensor} do
      now = DateTime.utc_now()
      ts = today_start()

      # 3 days ago has rain (to stop the counter)
      three_days_ago = DateTime.add(ts, -3 * 86400 + 3600, :second)
      record_rain_interval!(sensor, 5.0, three_days_ago)

      # today, yesterday, day-before all have zero readings (or none)
      # Insert explicit zero readings to make sure the sensor exists for those days
      record_rain_interval!(sensor, 0.0, DateTime.add(ts, -1 * 86400 + 3600, :second))
      record_rain_interval!(sensor, 0.0, DateTime.add(ts, -2 * 86400 + 3600, :second))

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      assert summary.days_without_rain == 3
    end

    test "stops counting when a rainy day is found", %{
      user: user,
      station: station,
      sensor: sensor
    } do
      now = DateTime.utc_now()
      ts = today_start()

      # Yesterday had rain (stops at 1)
      yesterday_rain = DateTime.add(ts, -86400 + 3600, :second)
      record_rain_interval!(sensor, 3.0, yesterday_rain)

      assert {:ok, summary} = Measurements.rain_summary(station.id, %{at: now}, actor: user)
      # Today is dry (no readings), yesterday had rain → 1 dry day (today)
      assert summary.days_without_rain == 1
    end
  end
end
