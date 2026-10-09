defmodule ExCurlImpersonate.RequestConfiguration do
  @moduledoc false

  defstruct headers: %{}, url: "", method: "", body: "", flags: %{}

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
        http_version: http_version(opts[:http_version])
      }
    }
  end

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
    headers = opts[:headers] || %{}

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
