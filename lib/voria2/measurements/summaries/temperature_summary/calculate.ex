defmodule Voria2.Measurements.Summaries.TemperatureSummary.Calculate do
  use Ash.Resource.Actions.Implementation

  alias Voria2.Measurements
  alias Voria2.Measurements.Summaries.Helpers
  alias Voria2.Measurements.Summaries.TemperatureSummary

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
        sensor = Helpers.find_active_sensor(station_id, "temperature")

        if sensor do
          do_calculate(sensor.id, at, offset_seconds)
        else
          {:ok,
           %TemperatureSummary{
             current: nil,
             trend: :stable,
             min_today: nil,
             max_today: nil,
             diff_24h: nil,
             history: []
           }}
        end
    end
  end

  defp do_calculate(sensor_id, at, offset_seconds) do
    {window_from, window_to} = Helpers.resolve_window(at, offset_seconds)
    today_start = Helpers.local_midnight(at)

    readings =
      Measurements.temperature_for_sensor!(sensor_id, window_from, window_to, authorize?: false)

    today_readings =
      Measurements.temperature_for_sensor!(sensor_id, today_start, at, authorize?: false)

    ago_24h = DateTime.add(at, -86400, :second)
    search_from = DateTime.add(ago_24h, -1800, :second)
    search_to = DateTime.add(ago_24h, 1800, :second)

    around_24h =
      Measurements.temperature_for_sensor!(sensor_id, search_from, search_to, authorize?: false)

    current =
      case List.last(readings) do
        nil -> nil
        r -> r.value
      end

    trend = Helpers.compute_trend(Enum.take(readings, -3), 0.1)

    {min_today, max_today} =
      case today_readings do
        [] ->
          {nil, nil}

        rs ->
          min_r = Enum.min_by(rs, & &1.value)
          max_r = Enum.max_by(rs, & &1.value)

          {%{value: min_r.value, at: min_r.measured_at},
           %{value: max_r.value, at: max_r.measured_at}}
      end

    diff_24h =
      case {current, find_closest(around_24h, ago_24h)} do
        {nil, _} -> nil
        {_, nil} -> nil
        {curr, closest} -> curr - closest.value
      end

    history = Enum.map(readings, fn r -> %{t: r.measured_at, v: r.value} end)

    {:ok,
     %TemperatureSummary{
       current: current,
       trend: trend,
       min_today: min_today,
       max_today: max_today,
       diff_24h: diff_24h,
       history: history
     }}
  end

  defp find_closest([], _target), do: nil

  defp find_closest(readings, target) do
    Enum.min_by(readings, fn r -> abs(DateTime.diff(r.measured_at, target, :second)) end)
  end
end
