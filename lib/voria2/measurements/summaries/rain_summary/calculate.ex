defmodule Voria2.Measurements.Summaries.RainSummary.Calculate do
  use Ash.Resource.Actions.Implementation

  alias Voria2.Measurements
  alias Voria2.Measurements.Summaries.Helpers
  alias Voria2.Measurements.Summaries.RainSummary

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    station_id = input.arguments.station_id
    at = input.arguments.at
    offset_seconds = input.arguments.offset_seconds

    case Helpers.authorize_station(actor, station_id) do
      {:error, :forbidden} ->
        {:error, Ash.Error.Forbidden.exception([])}

      {:ok, _station} ->
        sensor = Helpers.find_active_sensor(station_id, "rain")

        if sensor do
          do_calculate(sensor.id, at, offset_seconds)
        else
          {:ok,
           %RainSummary{
             total_today: 0.0,
             instant_rain: 0.0,
             rain_rate: 0.0,
             days_without_rain: 0
           }}
        end
    end
  end

  defp do_calculate(sensor_id, at, offset_seconds) do
    {window_from, window_to} = Helpers.resolve_window(at, offset_seconds)
    today_start = Helpers.local_midnight(at)

    readings =
      Measurements.rain_for_sensor!(sensor_id, window_from, window_to, authorize?: false)

    today_readings =
      Measurements.rain_for_sensor!(sensor_id, today_start, at, authorize?: false)

    total_today = Enum.reduce(today_readings, 0.0, fn r, acc -> acc + r.interval_mm end)

    instant_rain =
      case List.last(readings) do
        nil -> 0.0
        r -> r.interval_mm
      end

    rain_rate = compute_rain_rate(readings)
    days_dry = count_dry_days(sensor_id, today_start, at, 0, 365)

    {:ok,
     %RainSummary{
       total_today: total_today,
       instant_rain: instant_rain,
       rain_rate: rain_rate,
       days_without_rain: days_dry
     }}
  end

  defp compute_rain_rate(readings) do
    recent = Enum.take(readings, -10)
    n = length(recent)

    if n < 2 do
      0.0
    else
      gaps =
        recent
        |> Enum.map(& &1.measured_at)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> DateTime.diff(b, a, :second) end)

      avg_gap = Enum.sum(gaps) / length(gaps)

      if avg_gap <= 0 do
        0.0
      else
        avg_mm = Enum.sum(Enum.map(recent, & &1.interval_mm)) / n
        avg_mm * (3600.0 / avg_gap)
      end
    end
  end

  # Walks backwards one UTC day at a time counting consecutive dry days.
  # Starts from today's partial window (today_start..at), then full days backwards.
  defp count_dry_days(_sensor_id, _day_start, _day_end, count, max_days)
       when count >= max_days,
       do: count

  defp count_dry_days(sensor_id, day_start, day_end, count, max_days) do
    readings =
      Measurements.rain_for_sensor!(sensor_id, day_start, day_end, authorize?: false)

    total = Enum.reduce(readings, 0.0, fn r, acc -> acc + r.interval_mm end)

    if total > 0 do
      # This period has rain — stop counting
      count
    else
      # This period is dry — step back one full day
      prev_end = day_start
      prev_start = DateTime.add(day_start, -86400, :second)
      count_dry_days(sensor_id, prev_start, prev_end, count + 1, max_days)
    end
  end
end
