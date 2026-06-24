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
    days_dry = count_dry_days(sensor_id, today_start, at, 365)

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

  # Counts consecutive dry days ending today using a SINGLE grouped query
  # instead of recursing one day at a time (which previously did up to 365
  # sequential hypertable round-trips). A day is "dry" when its summed
  # interval_mm is 0, including days that have no readings at all.
  defp count_dry_days(sensor_id, today_start, at, max_days) do
    import Ecto.Query

    window_start = DateTime.add(today_start, -max_days * 86_400, :second)

    rows =
      Voria2.Repo.all(
        from r in Voria2.Measurements.RainMeasurement,
          where:
            r.sensor_installation_id == ^sensor_id and
              r.measured_at >= ^window_start and
              r.measured_at <= ^at,
          group_by: fragment("date_trunc('day', ?)", r.measured_at),
          select: {fragment("date_trunc('day', ?)::date", r.measured_at), sum(r.interval_mm)}
      )

    totals_by_date = Map.new(rows, fn {day, total} -> {day, total || 0.0} end)

    today_date = DateTime.to_date(today_start)
    oldest_date = Date.add(today_date, -max_days)

    Stream.iterate(today_date, &Date.add(&1, -1))
    |> Stream.take_while(&(Date.compare(&1, oldest_date) != :lt))
    |> Enum.reduce_while(0, fn date, count ->
      cond do
        count >= max_days -> {:halt, count}
        Map.get(totals_by_date, date, 0.0) > 0 -> {:halt, count}
        true -> {:cont, count + 1}
      end
    end)
  end
end
