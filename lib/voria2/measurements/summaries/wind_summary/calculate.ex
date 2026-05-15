defmodule Voria2.Measurements.Summaries.WindSummary.Calculate do
  use Ash.Resource.Actions.Implementation

  alias Voria2.Measurements
  alias Voria2.Measurements.Summaries.Helpers
  alias Voria2.Measurements.Summaries.WindSummary

  @sectors [
    {"N", 0},
    {"NNE", 22.5},
    {"NE", 45},
    {"ENE", 67.5},
    {"E", 90},
    {"ESE", 112.5},
    {"SE", 135},
    {"SSE", 157.5},
    {"S", 180},
    {"SSW", 202.5},
    {"SW", 225},
    {"WSW", 247.5},
    {"W", 270},
    {"WNW", 292.5},
    {"NW", 315},
    {"NNW", 337.5}
  ]

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
        sensor = Helpers.find_active_sensor(station_id, "wind")

        if sensor do
          do_calculate(sensor.id, at, offset_seconds)
        else
          {:ok,
           %WindSummary{
             current_speed: nil,
             current_direction: nil,
             current_gust: nil,
             max_gust_today: nil,
             wind_rose: []
           }}
        end
    end
  end

  defp do_calculate(sensor_id, at, offset_seconds) do
    {window_from, window_to} = Helpers.resolve_window(at, offset_seconds)
    today_start = Helpers.local_midnight(at)

    readings =
      Measurements.wind_for_sensor!(sensor_id, window_from, window_to, authorize?: false)

    today_readings =
      Measurements.wind_for_sensor!(sensor_id, today_start, at, authorize?: false)

    {current_speed, current_direction, current_gust} =
      case List.last(readings) do
        nil -> {nil, nil, nil}
        r -> {wind_speed(r.u, r.v), direction_deg(r.u, r.v), r.gust}
      end

    max_gust_today =
      today_readings
      |> Enum.filter(fn r -> not is_nil(r.gust) end)
      |> case do
        [] ->
          nil

        rs ->
          r = Enum.max_by(rs, & &1.gust)
          %{gust: r.gust, at: r.measured_at}
      end

    wind_rose = compute_wind_rose(readings)

    {:ok,
     %WindSummary{
       current_speed: current_speed,
       current_direction: current_direction,
       current_gust: current_gust,
       max_gust_today: max_gust_today,
       wind_rose: wind_rose
     }}
  end

  defp compute_wind_rose([]), do: []

  defp compute_wind_rose(readings) do
    total = length(readings)

    readings
    |> Enum.group_by(fn r -> sector_for(direction_deg(r.u, r.v)) end)
    |> Enum.map(fn {{name, _deg}, rs} ->
      %{sector: name, count: length(rs), pct: length(rs) / total * 100.0}
    end)
    |> Enum.sort_by(& &1.sector)
  end

  defp wind_speed(u, v), do: :math.sqrt(u * u + v * v)

  defp direction_deg(u, v) do
    deg = :math.atan2(u, v) * 180.0 / :math.pi()
    mod(deg + 180.0, 360.0)
  end

  defp mod(a, b) do
    r = :math.fmod(a, b)
    if r < 0, do: r + b, else: r
  end

  defp sector_for(deg) do
    idx = trunc(Float.floor((mod(deg, 360.0) + 11.25) / 22.5)) |> rem(16)
    Enum.at(@sectors, idx)
  end
end
