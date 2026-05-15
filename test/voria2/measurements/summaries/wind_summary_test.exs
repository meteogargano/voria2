defmodule Voria2.Measurements.Summaries.WindSummaryTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "wind", storage_type: :wind)
    sensor = create_sensor_installation(station, mt)
    %{user: user, station: station, sensor: sensor}
  end

  defp at_offset(base, seconds), do: DateTime.add(base, seconds, :second)

  # direction_deg(u,v) = mod(atan2(u,v)*180/pi + 180, 360)
  # Cardinal: u=0,v=-1→0°(N), u=-1,v=0→90°(E), u=0,v=1→180°(S), u=1,v=0→270°(W)

  describe "wind rose sector assignments (WMO floor formula)" do
    defp sector_for_direction(user, station, sensor, u, v) do
      # Use a time much in the past to avoid hypertable insertion issues
      # 2 hours ago
      at = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      record_wind!(sensor, u, v, measured_at: at)
      # Query with window 3 hours in past to 1 hour in future to ensure reading is included
      assert {:ok, summary} =
               Measurements.wind_summary(
                 station.id,
                 %{at: DateTime.add(at, 3600, :second), offset_seconds: -7200},
                 actor: user
               )

      entry = Enum.find(summary.wind_rose, fn e -> e.pct > 0 end)
      entry && entry.sector
    end

    test "0.0° → N (pure north)", %{user: user, station: station, sensor: sensor} do
      # u=0, v=-1 → 0°
      sector = sector_for_direction(user, station, sensor, 0.0, -1.0)
      assert sector == "N"
    end

    test "90.0° → E (pure east)", %{user: user, station: station, sensor: sensor} do
      # u=-1, v=0 → 90°
      sector = sector_for_direction(user, station, sensor, -1.0, 0.0)
      assert sector == "E"
    end

    test "270.0° → W (pure west)", %{user: user, station: station, sensor: sensor} do
      # u=1, v=0 → 270°
      sector = sector_for_direction(user, station, sensor, 1.0, 0.0)
      assert sector == "W"
    end

    test "NW sector (u=3, v=-4 → 323.13°)", %{user: user, station: station, sensor: sensor} do
      # atan2(3, -4) * 180/π ≈ 143.13°, then (143.13 + 180) mod 360 = 323.13°
      # 323.13° is in NW sector (315° center), not NNW (337.5° center)
      sector = sector_for_direction(user, station, sensor, 3.0, -4.0)
      assert sector == "NW"
    end
  end

  describe "wind rose counts" do
    test "4 readings all from north → N:100%", %{user: user, station: station, sensor: sensor} do
      at = DateTime.utc_now()

      for i <- 1..4 do
        record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -(i * 10)))
      end

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: at}, actor: user)
      n_entry = Enum.find(summary.wind_rose, &(&1.sector == "N"))
      assert n_entry != nil
      assert_in_delta n_entry.pct, 100.0, 0.001
      assert Enum.all?(summary.wind_rose, fn e -> e.sector == "N" or e.pct == 0.0 end)
    end

    test "2×N + 2×S → N:50%, S:50%", %{user: user, station: station, sensor: sensor} do
      at = DateTime.utc_now()

      # N: u=0, v=-1
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -40))
      record_wind!(sensor, 0.0, -1.0, measured_at: at_offset(at, -30))
      # S: u=0, v=1
      record_wind!(sensor, 0.0, 1.0, measured_at: at_offset(at, -20))
      record_wind!(sensor, 0.0, 1.0, measured_at: at_offset(at, -10))

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: at}, actor: user)
      n_entry = Enum.find(summary.wind_rose, &(&1.sector == "N"))
      s_entry = Enum.find(summary.wind_rose, &(&1.sector == "S"))
      assert n_entry != nil
      assert s_entry != nil
      assert_in_delta n_entry.pct, 50.0, 0.001
      assert_in_delta s_entry.pct, 50.0, 0.001
      # Only N and S sectors in the rose
      assert length(summary.wind_rose) == 2
    end
  end

  describe "current_speed and current_direction" do
    test "u=3, v=-4 → speed≈5.0, direction≈323.13° (NNW)", %{
      user: user,
      station: station,
      sensor: sensor
    } do
      at = DateTime.utc_now()
      record_wind!(sensor, 3.0, -4.0, measured_at: at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: at}, actor: user)
      assert_in_delta summary.current_speed, 5.0, 0.001
      assert_in_delta summary.current_direction, 323.13, 0.05
    end
  end

  describe "max_gust_today" do
    test "selects reading with highest gust", %{user: user, station: station, sensor: sensor} do
      now = DateTime.utc_now()
      today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

      t1 = DateTime.add(today_start, 3600, :second)
      t2 = DateTime.add(today_start, 7200, :second)
      t3 = DateTime.add(now, -10 * 60, :second)

      record_wind!(sensor, 1.0, 0.0, measured_at: t1, gust: 5.0)
      record_wind!(sensor, 1.0, 0.0, measured_at: t2, gust: 15.0)
      record_wind!(sensor, 1.0, 0.0, measured_at: t3, gust: 10.0)

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: now}, actor: user)
      assert summary.max_gust_today != nil
      assert summary.max_gust_today.gust == 15.0
    end

    test "nil when no gusts recorded today", %{user: user, station: station, sensor: sensor} do
      at = DateTime.utc_now()
      record_wind!(sensor, 1.0, 0.0, measured_at: at_offset(at, -30 * 60))

      assert {:ok, summary} = Measurements.wind_summary(station.id, %{at: at}, actor: user)
      assert is_nil(summary.max_gust_today)
    end
  end

  test "public read: other user can compute summary for any station", %{station: station} do
    other = create_user()
    # Summaries are public data - anyone can compute them
    assert {:ok, summary} = Measurements.wind_summary(station.id, actor: other)
    # No data yet
    assert is_nil(summary.current_speed)
  end
end
