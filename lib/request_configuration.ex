defmodule ExCurlImpersonate.RequestConfiguration do
  @moduledoc false

  defstruct headers: %{},
            url: "",
            method: "",
            body: "",
            flags: %{},
            long_opts: %{},
            string_opts: %{},
            slist_opts: %{}

  # plain curl options and curl-impersonate CURLOPT_* additions; names must match the Zig tables in ExCurlImpersonate.Request
  @long_opts ~w(timeout_ms connect_timeout_ms http2_no_priority http2_window_update http3_ssl_permute_extensions
                proxy_credential_no_reuse quic_initial_packet_number split_cookies
                ssl_enable_alps ssl_enable_ticket ssl_permute_extensions stream_exclusive
                tls_grease tls_key_shares_limit tls_key_usage_no_check tls_record_size_limit
                tls_signed_cert_timestamps tls_status_request tls_use_new_alps_codepoint
                ws_ssl_disable_ticket)a
  @string_opts ~w(cainfo capath interface form_boundary http2_pseudo_headers_order http2_settings http2_streams
                  http3_httpheader_order http3_pseudo_headers_order http3_settings
                  http3_sig_hash_algs http3_ssl_ec_curves http3_tls_extension_order
                  httpheader_order quic_cid_length quic_transport_parameters
                  ssl_cert_compression ssl_sig_hash_algs tls_delegated_credentials
                  tls_extension_order tls_trust_anchors ws_httpheader_order
                  ws_ssl_cert_compression)a
  @slist_opts ~w(httpbaseheader http3_httpheader ws_httpheader)a

  def long_opts, do: @long_opts
  def string_opts, do: @string_opts
  def slist_opts, do: @slist_opts

  @http_versions %{
    http1_0: 1,
    http1_1: 2,
    http2: 3,
    http2_tls: 4,
    http2_prior_knowledge: 5,
    http3: 30,
    http3_only: 31
  }

  def build(method, url, opts \\ []) do
    %__MODULE__{
      headers: get_headers(opts) |> convert_to_key_value_map(),
      url: url,
      method: method,
      body: Keyword.get(opts, :body, ""),
      flags: %{
        follow_location: Keyword.get(opts, :follow_location, true),
        ssl_verifyhost: Keyword.get(opts, :ssl_verifyhost, true),
        ssl_verifypeer: Keyword.get(opts, :ssl_verifypeer, true),
        return_metrics: Keyword.get(opts, :return_metrics, false),
        verbose: Keyword.get(opts, :verbose, false),
        proxy: Keyword.get(opts, :proxy, nil),
        impersonate: impersonate(opts[:impersonate]),
        impersonate_default_headers: Keyword.get(opts, :impersonate_default_headers, true),
        http_version: http_version(opts[:http_version]),
        accept_encoding: accept_encoding(Keyword.get(opts, :accept_encoding, ""))
      },
      long_opts: Map.new(@long_opts, &{&1, long_value(&1, opts[&1])}),
      string_opts: Map.new(@string_opts, &{&1, string_value(&1, opts[&1])}),
      slist_opts: Map.new(@slist_opts, &{&1, slist_value(&1, opts[&1])})
    }
  end

  defp accept_encoding(false), do: nil
  defp accept_encoding(encoding) when is_binary(encoding), do: encoding
  defp accept_encoding(other), do: invalid!(:accept_encoding, "a string or false", other)

  defp long_value(_, nil), do: nil

  defp long_value(key, value) when key in [:timeout_ms, :connect_timeout_ms] do
    if is_integer(value) and value >= 0,
      do: value,
      else: invalid!(key, "a non-negative integer (milliseconds)", value)
  end

  defp long_value(_, true), do: 1
  defp long_value(_, false), do: 0
  defp long_value(_, value) when is_integer(value), do: value
  defp long_value(key, value), do: invalid!(key, "an integer or boolean", value)

  defp string_value(_, nil), do: nil
  defp string_value(_, value) when is_binary(value), do: value
  defp string_value(key, value), do: invalid!(key, "a string", value)

  defp slist_value(_, nil), do: nil

  defp slist_value(key, value) when is_list(value) do
    if Enum.all?(value, &is_binary/1), do: value, else: invalid!(key, "a list of strings", value)
  end

  defp slist_value(key, value), do: invalid!(key, "a list of strings", value)

  defp invalid!(key, expected, value),
    do: raise(ArgumentError, "expected #{inspect(key)} to be #{expected}, got: #{inspect(value)}")

  defp impersonate(nil), do: nil
  defp impersonate(target) when is_binary(target), do: target

  defp impersonate(other),
    do: raise(ArgumentError, "expected :impersonate to be a string, got: #{inspect(other)}")

  defp http_version(nil), do: nil

  defp http_version(version) do
    Map.get(@http_versions, version) ||
      raise ArgumentError,
            "expected :http_version to be one of #{inspect(Map.keys(@http_versions))}, got: #{inspect(version)}"
  end

  defp get_headers(opts) do
    headers = Map.new(opts[:headers] || %{})

    if opts[:impersonate],
      do: headers,
      else: add_header_if_not_exists(headers, "user-agent", "ex_curl_impersonate/0.1.0")
  end

  defp add_header_if_not_exists(headers, key, value) do
    case String.downcase(key) in Enum.map(Map.keys(headers), &String.downcase/1) do
      true -> headers
      false -> Map.put(headers, key, value)
    end
  end

  defp convert_to_key_value_map(headers) do
    Enum.map(headers, fn {key, value} -> %{key: key, value: header_value(value)} end)
  end

  defp header_value(value) when is_boolean(value) or is_number(value), do: "#{value}"
  defp header_value(value) when is_list(value), do: Enum.join(value, " ")
  defp header_value(value) when is_binary(value), do: value
end
