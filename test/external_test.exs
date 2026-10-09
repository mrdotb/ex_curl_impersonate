defmodule ExCurlImpersonate.ExternalTest do
  use ExUnit.Case, async: true

  # Hits the network; run with: mix test --only external
  @moduletag :external

  defp fingerprint(opts) do
    {:ok, resp} = ExCurlImpersonate.get("https://tls.peet.ws/api/all", opts)
    Jason.decode!(resp.body)
  end

  test "impersonating chrome changes the TLS and HTTP/2 fingerprint" do
    chrome = fingerprint(impersonate: "chrome136")
    plain = fingerprint([])
    firefox = fingerprint(impersonate: "firefox135")

    assert chrome["user_agent"] =~ "Chrome/136"
    assert chrome["http_version"] == "h2"
    refute chrome["tls"]["ja4"] == plain["tls"]["ja4"]
    # libcurl-impersonate's default HTTP/2 settings already match Chrome, so the
    # akamai hash only differs from a non-Chrome profile (Firefox), not from plain.
    refute chrome["http2"]["akamai_fingerprint_hash"] ==
             firefox["http2"]["akamai_fingerprint_hash"]

    # Chrome sends GREASE values; stock curl does not
    assert Enum.any?(chrome["tls"]["extensions"], &String.contains?(&1["name"], "GREASE"))
  end

  test "http3_only negotiates HTTP/3" do
    assert {:ok, %{http_version: :http3}} =
             ExCurlImpersonate.get("https://cloudflare-quic.com/",
               impersonate: "chrome136",
               http_version: :http3_only
             )
  end
end
