defmodule Voria2.Measurements.Summaries.HumidityPressureSummary.Calculate do
  use Ash.Resource.Actions.Implementation

  alias Voria2.Measurements
  alias Voria2.Measurements.Summaries.Helpers
  alias Voria2.Measurements.Summaries.HumidityPressureSummary

  # Magnus formula constants (Alduchov-Eskridge 1996)
  @a 17.625
  @b 243.04

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
        humidity_sensor = Helpers.find_active_sensor(station_id, "humidity")
        pressure_sensor = Helpers.find_active_sensor(station_id, "pressure")
        temp_sensor = Helpers.find_active_sensor(station_id, "temperature")

        cond do
          is_nil(humidity_sensor) ->
            {:error, "No active humidity sensor for station #{station_id}"}

          is_nil(pressure_sensor) ->
            {:error, "No active pressure sensor for station #{station_id}"}

          true ->
            do_calculate(humidity_sensor, pressure_sensor, temp_sensor, at, offset_seconds)
        end
    end
  end

  defp do_calculate(hum_sensor, pres_sensor, temp_sensor, at, offset_seconds) do
    {window_from, window_to} = Helpers.resolve_window(at, offset_seconds)
    today_start = Helpers.local_midnight(at)

    hum_readings =
      Measurements.humidity_for_sensor!(hum_sensor.id, window_from, window_to, authorize?: false)

    hum_today =
      Measurements.humidity_for_sensor!(hum_sensor.id, today_start, at, authorize?: false)

    current_humidity = hum_readings |> List.last() |> value_of()
    humidity_trend = Helpers.compute_trend(Enum.take(hum_readings, -3), 0.1)
    {min_hum, max_hum} = min_max_today(hum_today)

    pres_readings =
      Measurements.pressure_for_sensor!(pres_sensor.id, window_from, window_to, authorize?: false)

    pres_today =
      Measurements.pressure_for_sensor!(pres_sensor.id, today_start, at, authorize?: false)

    current_pressure = pres_readings |> List.last() |> value_of()
    pressure_trend = Helpers.compute_trend(Enum.take(pres_readings, -3), 0.05)
    {min_pres, max_pres} = min_max_today(pres_today)

    dewpoint =
      case temp_sensor do
        nil ->
          nil

        ts ->
          temp_readings =
            Measurements.temperature_for_sensor!(ts.id, window_from, window_to, authorize?: false)

          current_temp = temp_readings |> List.last() |> value_of()

          case {current_temp, current_humidity} do
            {nil, _} -> nil
            {_, nil} -> nil
            {_t, rh} when rh <= 0 -> nil
            {t, rh} -> compute_dewpoint(t, rh)
          end
      end

    {:ok,
     %HumidityPressureSummary{
       current_humidity: current_humidity,
       humidity_trend: humidity_trend,
       min_humidity_today: min_hum,
       max_humidity_today: max_hum,
       current_pressure: current_pressure,
       pressure_trend: pressure_trend,
       min_pressure_today: min_pres,
       max_pressure_today: max_pres,
       dewpoint: dewpoint,
       barometer_trend: pressure_trend
     }}
  end

  defp compute_dewpoint(temp_c, rh_pct) do
    g = :math.log(rh_pct / 100.0) + @a * temp_c / (@b + temp_c)
    @b * g / (@a - g)
  end

  defp value_of(nil), do: nil
  defp value_of(%{value: v}), do: v

  defp min_max_today([]), do: {nil, nil}

  defp min_max_today(readings) do
    min_r = Enum.min_by(readings, & &1.value)
    max_r = Enum.max_by(readings, & &1.value)
    {%{value: min_r.value, at: min_r.measured_at}, %{value: max_r.value, at: max_r.measured_at}}
  end
end
