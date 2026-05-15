defmodule Voria2Web.IngestController do
  use Voria2Web, :controller

  def verify(conn, _params) do
    station = conn.assigns.ingest_station
    json(conn, %{ok: true, station_id: station.id, station_name: station.name})
  end

  def create(conn, params) do
    station = conn.assigns.ingest_station

    case Voria2.Ingest.dispatch(station, params) do
      :ok ->
        conn |> put_status(201) |> json(%{ok: true})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def bulk(conn, %{"_json" => items}) when is_list(items) do
    station = conn.assigns.ingest_station

    results =
      Enum.with_index(items)
      |> Enum.map(fn {params, i} ->
        case Voria2.Ingest.dispatch(station, params) do
          :ok -> %{index: i, ok: true}
          {:error, reason} -> %{index: i, ok: false, error: format_error(reason)}
        end
      end)

    ok_count = Enum.count(results, & &1.ok)
    conn |> json(%{ok: true, count: ok_count, results: results})
  end

  def bulk(conn, _) do
    conn |> put_status(422) |> json(%{ok: false, error: "body must be a JSON array"})
  end

  defp format_error({:missing_fields, fields}),
    do: "missing required fields: #{Enum.join(fields, ", ")}"

  defp format_error({:unknown_sensor, slug}), do: "unknown sensor slug: #{slug}"
  defp format_error({:invalid_field, field, msg}), do: "#{field}: #{msg}"
  defp format_error(other), do: inspect(other)
end
