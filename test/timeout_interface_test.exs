defmodule ExCurlImpersonate.TimeoutInterfaceTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.TestClient

  setup do
    {:ok, bypass: Bypass.open()}
  end

  test "timeout_ms aborts a request to a server that never answers" do
    # accepts the TCP connection but never sends a byte
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    on_exit(fn -> :gen_tcp.close(listen) end)

    {elapsed_us, result} =
      :timer.tc(fn -> TestClient.get("http://127.0.0.1:#{port}/hang", timeout_ms: 200) end)

    assert result == {:error, "OPERATION_TIMEDOUT"}
    assert elapsed_us < 1_500_000
  end

  test "connect_timeout_ms is accepted and does not affect a fast request", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/fast", &Plug.Conn.send_resp(&1, 200, "ok"))

    assert {:ok, %{body: "ok"}} =
             TestClient.get("http://localhost:#{bypass.port}/fast", connect_timeout_ms: 1_000)
  end

  test "interface binds the outgoing connection", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/ip", fn conn ->
      Plug.Conn.send_resp(conn, 200, conn.remote_ip |> :inet.ntoa() |> to_string())
    end)

    assert {:ok, %{body: "127.0.0.1"}} =
             TestClient.get("http://127.0.0.1:#{bypass.port}/ip", interface: "127.0.0.1")
  end

  test "an unknown interface returns an error" do
    assert {:error, "INTERFACE_FAILED"} =
             TestClient.get("http://127.0.0.1:1/", interface: "nonexistent-if0")
  end

  test "resolve pins a name to an address", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/pinned", &Plug.Conn.send_resp(&1, 200, "pinned"))

    assert {:ok, %{body: "pinned"}} =
             TestClient.get("http://pinned.invalid:#{bypass.port}/pinned",
               resolve: ["pinned.invalid:#{bypass.port}:127.0.0.1"]
             )
  end

  test "without resolve the same name does not resolve" do
    assert {:error, "COULDNT_RESOLVE_HOST"} = TestClient.get("http://pinned.invalid:1/")
  end

  test "ip_resolve restricts the address family", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/family", &Plug.Conn.send_resp(&1, 200, "ok"))
    pin = ["dual.invalid:#{bypass.port}:127.0.0.1"]
    url = "http://dual.invalid:#{bypass.port}/family"

    assert {:ok, %{body: "ok"}} = TestClient.get(url, resolve: pin, ip_resolve: :v4)
    assert {:error, _reason} = TestClient.get(url, resolve: pin, ip_resolve: :v6)
  end

  test "ip_resolve rejects anything but :any, :v4 and :v6" do
    assert_raise ArgumentError, ~r/:ip_resolve/, fn ->
      TestClient.get("http://127.0.0.1:1/", ip_resolve: :ipv6)
    end
  end
end
