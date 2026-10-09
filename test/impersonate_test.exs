defmodule ExCurlImpersonate.ImpersonateTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.TestClient

  setup do
    {:ok, bypass: Bypass.open()}
  end

  defp echo_headers(bypass) do
    Bypass.expect(bypass, "GET", "/h", fn conn ->
      Plug.Conn.send_resp(conn, 200, Jason.encode!(Map.new(conn.req_headers)))
    end)
  end

  defp get_headers(bypass, opts) do
    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/h", opts)
    Jason.decode!(resp.body)
  end

  test "impersonate sends the browser's default headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136")
    assert headers["sec-ch-ua"] =~ "Chrome"
    assert "Mozilla/5.0" <> _ = headers["user-agent"]
  end

  test "impersonate_default_headers: false omits them", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", impersonate_default_headers: false)
    refute Map.has_key?(headers, "sec-ch-ua")
    refute String.starts_with?(headers["user-agent"] || "", "ex_curl_impersonate/")
  end

  test "a user-supplied user-agent overrides the preset", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", headers: %{"user-agent" => "mine"})
    assert headers["user-agent"] == "mine"
  end

  test "unknown impersonate target returns an error" do
    assert {:error, "BAD_FUNCTION_ARGUMENT"} =
             ExCurlImpersonate.get("http://localhost:1/", impersonate: "netscape4")
  end

  test "reports the negotiated http version", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/v", &Plug.Conn.send_resp(&1, 200, "OK"))
    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/v")
    assert resp.http_version == :http1_1
  end

  test "http_version: :http1_0 is honoured", %{bypass: bypass} do
    test_pid = self()

    Bypass.expect(bypass, "GET", "/v", fn conn ->
      send(test_pid, {:protocol, Plug.Conn.get_http_protocol(conn)})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    {:ok, %{status_code: 200}} =
      TestClient.get("http://localhost:#{bypass.port}/v", http_version: :http1_0)

    # the server (cowboy) always answers HTTP/1.1, so assert on what it received
    assert_receive {:protocol, :"HTTP/1.0"}
  end

  test "httpbaseheader replaces the preset base headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", httpbaseheader: ["x-base: 1"])
    assert headers["x-base"] == "1"
    refute Map.has_key?(headers, "sec-ch-ua")
  end

  test "httpbaseheader: [] clears the preset base headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", httpbaseheader: [])
    refute Map.has_key?(headers, "sec-ch-ua")
  end

  test "long and string options are accepted by curl", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/v", &Plug.Conn.send_resp(&1, 200, "OK"))

    assert {:ok, %{status_code: 200}} =
             TestClient.get("http://localhost:#{bypass.port}/v",
               tls_grease: true,
               ssl_enable_ticket: false,
               http2_settings: "1:65536;4:6291456",
               tls_extension_order: "0-23-65281-10-11-35-16-5-13-18-51-45-43-27-17513"
             )
  end

  # A bare listening socket lets the TCP connect succeed, so curl reaches the
  # TLS layer and loads the CA file, which is where :cainfo takes effect.
  test "cainfo reaches curl" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen)

    assert {:error, reason} =
             TestClient.get("https://localhost:#{port}/", cainfo: "/nonexistent/ca.pem")

    :gen_tcp.close(listen)
    assert reason =~ "SSL_CACERT_BADFILE"
  end
end
