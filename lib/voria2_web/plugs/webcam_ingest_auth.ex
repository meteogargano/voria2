defmodule Voria2Web.Plugs.WebcamIngestAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_api_key(conn) do
      {:ok, api_key} ->
        case Voria2.Cache.webcam_for_key(api_key) do
          {:ok, webcam} when not is_nil(webcam) ->
            assign(conn, :ingest_webcam, webcam)

          _ ->
            send_error(conn, 401, "invalid_api_key")
        end

      :error ->
        send_error(conn, 401, "missing_api_key")
    end
  end

  defp extract_api_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [api_key] when byte_size(api_key) > 0 ->
        {:ok, api_key}

      _ ->
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
