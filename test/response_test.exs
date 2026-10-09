defmodule ExCurlImpersonate.ResponseTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.Response

  defp parse_headers(raw) do
    Response.parse(%{body: "", status_code: 200, headers: raw, http_version: 2, metrics: nil}).headers
  end

  test "keeps only the final response's headers" do
    raw =
      "HTTP/1.1 302 Found\r\nlocation: /end\r\nx-hop: redirect\r\n\r\n" <>
        "HTTP/1.1 200 OK\r\ncontent-type: text/html\r\n\r\n"

    assert parse_headers(raw) == %{"content-type" => "text/html"}
  end

  test "skips interim 1xx responses" do
    raw =
      "HTTP/1.1 101 Switching Protocols\r\nconnection: Upgrade\r\n\r\n" <>
        "HTTP/2 200\r\ncontent-type: text/html\r\n\r\n"

    assert parse_headers(raw) == %{"content-type" => "text/html"}
  end

  test "collects every set-cookie into a list" do
    raw = "HTTP/1.1 200 OK\r\nset-cookie: a=1; Path=/\r\nset-cookie: b=2\r\n\r\n"
    assert parse_headers(raw) == %{"set-cookie" => ["a=1; Path=/", "b=2"]}
  end

  test "a single set-cookie is still a list" do
    assert parse_headers("HTTP/1.1 200 OK\r\nset-cookie: a=1\r\n\r\n") == %{
             "set-cookie" => ["a=1"]
           }
  end

  test "joins other repeated headers with a comma" do
    raw = "HTTP/1.1 200 OK\r\nvary: accept\r\nvary: origin\r\n\r\n"
    assert parse_headers(raw) == %{"vary" => "accept, origin"}
  end

  test "keeps colons in values and tolerates missing space after the colon" do
    raw = "HTTP/1.1 200 OK\r\nlocation: http://x:8080/a\r\nx-tight:value\r\n\r\n"
    assert parse_headers(raw) == %{"location" => "http://x:8080/a", "x-tight" => "value"}
  end
end
