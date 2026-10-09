defmodule ExCurlImpersonate.Response do
  @moduledoc """
  A valid response returned by ExCurlImpersonate.

  `headers` - the headers of the final response (headers of redirect hops and interim `1xx` responses are dropped).
  Repeated headers are joined with `", "`, except `set-cookie`, which is always a list of every cookie the server set.

  `http_version` - the HTTP version used for the response (`:http1_0`, `:http1_1`, `:http2`, `:http3`).

  ## Metrics

  When the `return_metrics` option is set to `true` for a request, the `metrics` field will be populated with a [`%ExCurlImpersonate.ResponseMetrics{}`](https://hexdocs.pm/ex_curl_impersonate/ExCurlImpersonate.ResponseMetrics.html) value.

  For example:

        iex> ExCurlImpersonate.get!("https://httpbin.org/get", return_metrics: true)
        %ExCurlImpersonate.Response{status_code: 200, metrics: %ExCurlImpersonate.ResponseMetrics{}, ...}

  """
  defstruct body: "",
            headers: %{},
            status_code: 200,
            http_version: nil,
            metrics: nil

  @type t :: %__MODULE__{
          body: nil | String.t(),
          headers: %{optional(String.t()) => String.t() | [String.t()]},
          status_code: integer(),
          http_version: nil | :http1_0 | :http1_1 | :http2 | :http3,
          metrics: nil | ExCurlImpersonate.ResponseMetrics.t()
        }

  @doc false
  def parse(raw) do
    response = struct(__MODULE__, raw)

    %{
      response
      | headers: header_string_to_map(response.headers),
        http_version: parse_http_version(response.http_version),
        metrics: parse_metrics(response.metrics)
    }
  end

  # curl hands us the header lines of every response in the chain (redirect
  # hops, 1xx/101 interim responses, proxy CONNECT); keep only the last one,
  # which is the response the body belongs to.
  defp header_string_to_map(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.reduce([], fn
      "HTTP/" <> _, _blocks_so_far -> []
      line, acc -> [line | acc]
    end)
    |> Enum.reverse()
    |> Enum.flat_map(&parse_header_line/1)
    |> Enum.group_by(fn {key, _} -> key end, fn {_, value} -> value end)
    |> Map.new(fn
      {"set-cookie" = key, values} -> {key, values}
      {key, values} -> {key, Enum.join(values, ", ")}
    end)
  end

  defp parse_header_line(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] when key != "" -> [{key, String.trim(value)}]
      _ -> []
    end
  end

  # CURLINFO_HTTP_VERSION values
  defp parse_http_version(1), do: :http1_0
  defp parse_http_version(2), do: :http1_1
  defp parse_http_version(3), do: :http2
  defp parse_http_version(30), do: :http3
  defp parse_http_version(_), do: nil

  defp parse_metrics(nil), do: nil

  defp parse_metrics(metrics) when is_map(metrics),
    do: struct(ExCurlImpersonate.ResponseMetrics, metrics)
end
