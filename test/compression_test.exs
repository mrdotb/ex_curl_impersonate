defmodule ExCurlImpersonate.CompressionTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.TestClient

  @html "<html>" <> String.duplicate("hello ", 200) <> "</html>"

  setup do
    bypass = Bypass.open()

    Bypass.expect(bypass, "GET", "/gz", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.send_resp(200, :zlib.gzip(@html))
    end)

    {:ok, url: "http://localhost:#{bypass.port}/gz"}
  end

  test "decodes compressed bodies by default", %{url: url} do
    {:ok, resp} = TestClient.get(url)
    assert resp.body == @html
  end

  test "decodes compressed bodies when impersonating", %{url: url} do
    {:ok, resp} = TestClient.get(url, impersonate: "chrome136")
    assert resp.body == @html
  end

  test "accept_encoding: false returns the raw bytes", %{url: url} do
    {:ok, resp} = TestClient.get(url, accept_encoding: false)
    assert :zlib.gunzip(resp.body) == @html
  end
end
