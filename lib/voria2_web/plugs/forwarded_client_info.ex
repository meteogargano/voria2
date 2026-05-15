defmodule Voria2Web.Plugs.ForwardedClientInfo do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @forwarded_ip_headers [
    {"true-client-ip", :true_client_ip},
    {"cf-connecting-ip", :cf_connecting_ip}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> put_private(:origin_remote_ip, conn.remote_ip)
      |> maybe_put_private(:cf_connecting_ipv6, single_header_ip(conn, "cf-connecting-ipv6"))
      |> maybe_put_private(:cloudflare_ray, single_header(conn, "cf-ray"))
      |> maybe_put_private(:cloudflare_ipcountry, single_header(conn, "cf-ipcountry"))

    case forwarded_client_ip(conn) do
      {:ok, remote_ip, source} ->
        conn
        |> put_private(:client_ip_source, source)
        |> put_remote_ip(remote_ip)

      :error ->
        put_private(conn, :client_ip_source, :peer)
    end
  end

  defp forwarded_client_ip(conn) do
    Enum.find_value(@forwarded_ip_headers, fn {header, source} ->
      case single_header_ip(conn, header) do
        nil -> nil
        remote_ip -> {:ok, remote_ip, source}
      end
    end) ||
      case first_forwarded_for_ip(conn) do
        nil -> :error
        remote_ip -> {:ok, remote_ip, :x_forwarded_for}
      end
  end

  defp first_forwarded_for_ip(conn) do
    conn
    |> get_req_header("x-forwarded-for")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&parse_ip/1)
    |> Enum.find(& &1)
  end

  defp single_header_ip(conn, header) do
    conn
    |> single_header(header)
    |> parse_ip()
  end

  defp single_header(conn, header) do
    conn
    |> get_req_header(header)
    |> List.first()
    |> case do
      nil ->
        nil

      value ->
        value = String.trim(value)

        if value == "" do
          nil
        else
          value
        end
    end
  end

  defp parse_ip(nil), do: nil

  defp parse_ip(candidate) do
    candidate = String.trim(candidate)

    case :inet.parse_address(String.to_charlist(candidate)) do
      {:ok, remote_ip} -> remote_ip
      {:error, :einval} -> nil
    end
  end

  defp maybe_put_private(conn, _key, nil), do: conn
  defp maybe_put_private(conn, key, value), do: put_private(conn, key, value)

  defp put_remote_ip(conn, remote_ip) do
    %Plug.Conn{} = conn
    %{conn | remote_ip: remote_ip}
  end
end
