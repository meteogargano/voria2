defmodule Voria2.Measurements.Summaries.Helpers do
  @moduledoc false

  require Ash.Query

  def resolve_window(at, offset_seconds) do
    {DateTime.add(at, offset_seconds, :second), at}
  end

  def local_midnight(at) do
    DateTime.new!(DateTime.to_date(at), ~T[00:00:00], "Etc/UTC")
  end

  def find_active_sensor(station_id, slug) do
    Voria2.Measurements.SensorInstallation
    |> Ash.Query.filter(station_id == ^station_id)
    |> Ash.Query.load(:measurement_type)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn si ->
      si.measurement_type.slug == slug and is_nil(si.removed_at)
    end)
  end

  def authorize_station(actor, station_id) do
    case Voria2.Network.get_station(station_id, actor: actor) do
      {:ok, station} -> {:ok, station}
      {:error, _} -> {:error, :forbidden}
    end
  end

  def linear_slope(ys) do
    n = length(ys)
    xs = Enum.to_list(0..(n - 1))
    xm = Enum.sum(xs) / n
    ym = Enum.sum(ys) / n
    num = Enum.zip(xs, ys) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - xm) * (y - ym) end)
    den = Enum.reduce(xs, 0.0, fn x, acc -> acc + (x - xm) * (x - xm) end)
    if den == 0.0, do: 0.0, else: num / den
  end

  def compute_trend(readings, threshold) do
    if length(readings) < 2 do
      :stable
    else
      ys = Enum.map(readings, & &1.value)
      slope = linear_slope(ys)

      cond do
        slope > threshold -> :rising
        slope < -threshold -> :falling
        true -> :stable
      end
    end
  end
end
