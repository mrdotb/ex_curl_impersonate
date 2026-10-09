defmodule ExCurlImpersonate.RequestConfigurationTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.RequestConfiguration

  defp header_keys(config), do: Enum.map(config.headers, &String.downcase(&1.key))

  test "impersonate defaults" do
    config = RequestConfiguration.build("GET", "http://x")
    assert config.flags.impersonate == nil
    assert config.flags.impersonate_default_headers == true
    assert config.flags.http_version == nil
  end

  test "adds the library user-agent only when not impersonating" do
    assert "user-agent" in header_keys(RequestConfiguration.build("GET", "http://x"))

    refute "user-agent" in header_keys(
             RequestConfiguration.build("GET", "http://x", impersonate: "chrome136")
           )
  end

  test "keeps a user-supplied user-agent when impersonating" do
    config =
      RequestConfiguration.build("GET", "http://x",
        impersonate: "chrome136",
        headers: %{"User-Agent" => "mine"}
      )

    assert [%{key: "User-Agent", value: "mine"}] = config.headers
  end

  test "maps http_version atoms to CURL_HTTP_VERSION values" do
    for {atom, value} <- [
          http1_0: 1,
          http1_1: 2,
          http2: 3,
          http2_tls: 4,
          http2_prior_knowledge: 5,
          http3: 30,
          http3_only: 31
        ] do
      assert RequestConfiguration.build("GET", "http://x", http_version: atom).flags.http_version ==
               value
    end
  end

  test "rejects invalid http_version and impersonate values" do
    assert_raise ArgumentError, ~r/:http_version/, fn ->
      RequestConfiguration.build("GET", "http://x", http_version: :http4)
    end

    assert_raise ArgumentError, ~r/:impersonate/, fn ->
      RequestConfiguration.build("GET", "http://x", impersonate: :chrome)
    end
  end
end
