defmodule Voria2Web.Plugs.IngestAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_api_key(conn) do
      {:ok, api_key} ->
        case Voria2.Cache.station_for_key(api_key) do
          {:ok, station} when not is_nil(station) ->
            assign(conn, :ingest_station, station)

          _ ->
            send_error(conn, 401, "invalid_api_key")
        end

      :error ->
        send_error(conn, 401, "missing_api_key")
    end
  end

  defp extract_api_key(conn) do
    # Try X-Api-Key header first
    case get_req_header(conn, "x-api-key") do
      [api_key] when byte_size(api_key) > 0 ->
        {:ok, api_key}

      _ ->
        # Try Authorization Bearer token
        case get_req_header(conn, "authorization") do
          ["Bearer " <> api_key] when byte_size(api_key) > 0 ->
            {:ok, api_key}

          _ ->
            :error
        end
    end
  end

  defp send_error(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, ~s({"error":"#{error}"}))
    |> halt()
  end
end
