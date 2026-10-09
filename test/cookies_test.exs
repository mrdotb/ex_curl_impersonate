defmodule ExCurlImpersonate.CookiesTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.TestClient

  setup do
    {:ok, bypass: Bypass.open()}
  end

  test "cookies set during a redirect are sent on the next hop", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/login", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("set-cookie", "session=abc; Path=/")
      |> Plug.Conn.put_resp_header("location", "/home")
      |> Plug.Conn.send_resp(302, "")
    end)

    Bypass.expect(bypass, "GET", "/home", fn conn ->
      Plug.Conn.send_resp(conn, 200, Enum.join(Plug.Conn.get_req_header(conn, "cookie"), ";"))
    end)

    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/login")
    assert resp.body =~ "session=abc"
  end

  test "multiple set-cookie headers are all returned", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/c", fn conn ->
      conn
      |> Plug.Conn.prepend_resp_headers([{"set-cookie", "a=1"}, {"set-cookie", "b=2"}])
      |> Plug.Conn.send_resp(200, "ok")
    end)

    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/c")
    assert Enum.sort(resp.headers["set-cookie"]) == ["a=1", "b=2"]
  end

  test "final headers after a redirect don't include the redirect's headers", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/start", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/end")
      |> Plug.Conn.put_resp_header("x-hop", "redirect")
      |> Plug.Conn.send_resp(302, "")
    end)

    Bypass.expect(bypass, "GET", "/end", &Plug.Conn.send_resp(&1, 200, "ok"))

    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/start")
    refute Map.has_key?(resp.headers, "x-hop")
    refute Map.has_key?(resp.headers, "location")
  end
end
