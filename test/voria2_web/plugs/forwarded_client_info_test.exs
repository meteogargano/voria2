defmodule Voria2Web.Plugs.ForwardedClientInfoTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias Voria2Web.Plugs.ForwardedClientInfo

  test "prefers true-client-ip over other forwarding headers" do
    conn =
      build_conn()
      |> with_remote_ip({10, 0, 0, 10})
      |> put_req_header("true-client-ip", "203.0.113.10")
      |> put_req_header("cf-connecting-ip", "203.0.113.11")
      |> put_req_header("x-forwarded-for", "198.51.100.20, 198.51.100.21")
      |> ForwardedClientInfo.call([])

    assert conn.remote_ip == {203, 0, 113, 10}
    assert conn.private.origin_remote_ip == {10, 0, 0, 10}
    assert conn.private.client_ip_source == :true_client_ip
  end

  test "falls back to x-forwarded-for when cloudflare header is invalid" do
    conn =
      build_conn()
      |> with_remote_ip({10, 0, 0, 11})
      |> put_req_header("cf-connecting-ip", "invalid")
      |> put_req_header("x-forwarded-for", "198.51.100.20, invalid")
      |> ForwardedClientInfo.call([])

    assert conn.remote_ip == {198, 51, 100, 20}
    assert conn.private.client_ip_source == :x_forwarded_for
  end

  test "preserves cloudflare ipv6 metadata" do
    conn =
      build_conn()
      |> with_remote_ip({10, 0, 0, 12})
      |> put_req_header("cf-connecting-ip", "240.0.0.2")
      |> put_req_header("cf-connecting-ipv6", "2001:db8::42")
      |> put_req_header("cf-ray", "abcd1234-FCO")
      |> put_req_header("cf-ipcountry", "IT")
      |> ForwardedClientInfo.call([])

    assert conn.remote_ip == {240, 0, 0, 2}
    assert conn.private.cf_connecting_ipv6 == {8193, 3512, 0, 0, 0, 0, 0, 66}
    assert conn.private.cloudflare_ray == "abcd1234-FCO"
    assert conn.private.cloudflare_ipcountry == "IT"
  end

  test "keeps the peer remote ip when no forwarded headers are present" do
    conn =
      build_conn()
      |> with_remote_ip({10, 0, 0, 13})
      |> ForwardedClientInfo.call([])

    assert conn.remote_ip == {10, 0, 0, 13}
    assert conn.private.origin_remote_ip == {10, 0, 0, 13}
    assert conn.private.client_ip_source == :peer
  end

  defp with_remote_ip(conn, remote_ip) do
    %Plug.Conn{} = conn
    %{conn | remote_ip: remote_ip}
  end
end
