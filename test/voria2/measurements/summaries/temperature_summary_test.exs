defmodule Voria2.Measurements.Summaries.TemperatureSummaryTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    %{user: user, station: station, sensor: sensor}
  end

  defp at_offset(base, seconds), do: DateTime.add(base, seconds, :second)

  # Use a fixed "now" 2 hours ago so readings we insert fall within the default 1-hour window
  defp window_at(offset_from_now \\ 0) do
    DateTime.add(DateTime.utc_now(), offset_from_now - 1800, :second)
  end

  test "no data: current is nil, trend is :stable, history is []", %{user: user, station: station} do
    at = DateTime.utc_now()
    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert is_nil(summary.current)
    assert summary.trend == :stable
    assert summary.history == []
  end

  test "single reading: current = value, trend = :stable", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    at = DateTime.utc_now()
    t = at_offset(at, -30 * 60)
    record_temperature!(sensor, 18.5, t)

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert summary.current == 18.5
    assert summary.trend == :stable
  end

  test "trend rising: [10.0, 11.0, 12.0]", %{user: user, station: station, sensor: sensor} do
    at = DateTime.utc_now()
    record_temperature!(sensor, 10.0, at_offset(at, -50 * 60))
    record_temperature!(sensor, 11.0, at_offset(at, -40 * 60))
    record_temperature!(sensor, 12.0, at_offset(at, -30 * 60))

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert summary.trend == :rising
  end

  test "trend falling: [12.0, 11.0, 10.0]", %{user: user, station: station, sensor: sensor} do
    at = DateTime.utc_now()
    record_temperature!(sensor, 12.0, at_offset(at, -50 * 60))
    record_temperature!(sensor, 11.0, at_offset(at, -40 * 60))
    record_temperature!(sensor, 10.0, at_offset(at, -30 * 60))

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert summary.trend == :falling
  end

  test "trend stable: slope < threshold 0.1", %{user: user, station: station, sensor: sensor} do
    at = DateTime.utc_now()
    # slope = 0.05 per step, below threshold 0.1
    record_temperature!(sensor, 10.0, at_offset(at, -50 * 60))
    record_temperature!(sensor, 10.05, at_offset(at, -40 * 60))
    record_temperature!(sensor, 10.1, at_offset(at, -30 * 60))

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert summary.trend == :stable
  end

  test "min_today and max_today select correct readings", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    now = DateTime.utc_now()
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    # Insert readings: one early today (low), one mid-day (high), one in window
    t_low = DateTime.add(today_start, 60, :second)
    t_high = DateTime.add(today_start, 3600, :second)
    t_window = DateTime.add(now, -30 * 60, :second)

    record_temperature!(sensor, 5.0, t_low)
    record_temperature!(sensor, 30.0, t_high)
    record_temperature!(sensor, 20.0, t_window)

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: now}, actor: user)
    assert summary.min_today.value == 5.0
    assert summary.max_today.value == 30.0
  end

  test "diff_24h: current minus value 24h ago", %{user: user, station: station, sensor: sensor} do
    now = DateTime.utc_now()
    t_24h_ago = DateTime.add(now, -86400, :second)
    t_recent = DateTime.add(now, -30 * 60, :second)

    record_temperature!(sensor, 10.0, t_24h_ago)
    record_temperature!(sensor, 15.0, t_recent)

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: now}, actor: user)
    assert_in_delta summary.diff_24h, 5.0, 0.001
  end

  test "history returned ascending by measured_at", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    at = DateTime.utc_now()
    record_temperature!(sensor, 10.0, at_offset(at, -50 * 60))
    record_temperature!(sensor, 12.0, at_offset(at, -40 * 60))
    record_temperature!(sensor, 14.0, at_offset(at, -30 * 60))

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    values = Enum.map(summary.history, & &1.v)
    assert values == [10.0, 12.0, 14.0]
  end

  test "window filter: readings outside window not included", %{
    user: user,
    station: station,
    sensor: sensor
  } do
    at = DateTime.utc_now()
    # offset_seconds=-3600 means window = [at-1h, at]
    inside = at_offset(at, -30 * 60)
    outside = at_offset(at, -90 * 60)

    record_temperature!(sensor, 20.0, inside)
    record_temperature!(sensor, 5.0, outside)

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: user)
    assert length(summary.history) == 1
    assert hd(summary.history).v == 20.0
  end

  test "public read: other user can compute summary for any station", %{station: station} do
    other = create_user()
    # Summaries are public data - anyone can compute them
    assert {:ok, summary} = Measurements.temperature_summary(station.id, actor: other)
    # No data yet
    assert summary.current == nil
  end

  test "admin bypass: admin can calculate on any station", %{station: station, sensor: sensor} do
    admin = create_admin()
    at = DateTime.utc_now()
    record_temperature!(sensor, 22.0, at_offset(at, -30 * 60))

    assert {:ok, summary} = Measurements.temperature_summary(station.id, %{at: at}, actor: admin)
    assert summary.current == 22.0
  end
end
