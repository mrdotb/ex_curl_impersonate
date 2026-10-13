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

  test "keyword-list headers work without :impersonate" do
    config = RequestConfiguration.build("GET", "http://x", headers: [{"x-a", "1"}])
    keys = Enum.map(config.headers, & &1.key)
    assert "x-a" in keys
    assert "user-agent" in keys
  end

  describe "fingerprint options" do
    test "default to nil" do
      config = RequestConfiguration.build("GET", "http://x")
      assert Enum.all?(Map.values(config.long_opts), &is_nil/1)
      assert Enum.all?(Map.values(config.string_opts), &is_nil/1)
      assert Enum.all?(Map.values(config.slist_opts), &is_nil/1)
      assert map_size(config.long_opts) == 21
      assert map_size(config.string_opts) == 23
      assert map_size(config.slist_opts) == 4
    end

    test "booleans become 1/0 and false is not dropped" do
      config =
        RequestConfiguration.build("GET", "http://x",
          tls_grease: true,
          ssl_enable_ticket: false,
          tls_record_size_limit: 4001
        )

      assert config.long_opts.tls_grease == 1
      assert config.long_opts.ssl_enable_ticket == 0
      assert config.long_opts.tls_record_size_limit == 4001
    end

    test "strings and lists pass through" do
      config =
        RequestConfiguration.build("GET", "http://x",
          http2_settings: "1:65536",
          httpbaseheader: ["a: 1"]
        )

      assert config.string_opts.http2_settings == "1:65536"
      assert config.slist_opts.httpbaseheader == ["a: 1"]
    end

    test "wrong types raise ArgumentError naming the option" do
      assert_raise ArgumentError, ~r/:tls_grease/, fn ->
        RequestConfiguration.build("GET", "http://x", tls_grease: "yes")
      end

      assert_raise ArgumentError, ~r/:http2_settings/, fn ->
        RequestConfiguration.build("GET", "http://x", http2_settings: 1)
      end

      assert_raise ArgumentError, ~r/:httpbaseheader/, fn ->
        RequestConfiguration.build("GET", "http://x", httpbaseheader: "a: 1")
      end
    end
  end

  test "accept_encoding defaults to all encodings and false disables it" do
    assert RequestConfiguration.build("GET", "http://x").flags.accept_encoding == ""

    assert RequestConfiguration.build("GET", "http://x", accept_encoding: "gzip").flags.accept_encoding ==
             "gzip"

    assert RequestConfiguration.build("GET", "http://x", accept_encoding: false).flags.accept_encoding ==
             nil

    assert_raise ArgumentError, ~r/:accept_encoding/, fn ->
      RequestConfiguration.build("GET", "http://x", accept_encoding: true)
    end
  end

  test "timeouts must be non-negative integers" do
    config =
      RequestConfiguration.build("GET", "http://x", timeout_ms: 5_000, connect_timeout_ms: 0)

    assert config.long_opts.timeout_ms == 5_000
    assert config.long_opts.connect_timeout_ms == 0

    for bad <- [true, -1, "5000"] do
      assert_raise ArgumentError, ~r/:timeout_ms/, fn ->
        RequestConfiguration.build("GET", "http://x", timeout_ms: bad)
      end
    end
  end
end
