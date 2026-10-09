defmodule ExCurlImpersonate.Response do
  @moduledoc """
  A valid response returned by ExCurlImpersonate.

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
          headers: map(),
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

  defp header_string_to_map(headers) do
    headers
    |> String.split("\r\n")
    |> Stream.filter(&String.contains?(&1, ":"))
    |> Stream.map(&String.split(&1, ": "))
    |> Stream.map(fn [head | rest] -> [head, Enum.join(rest, ": ")] end)
    |> Stream.map(fn [key, value] -> {key, value} end)
    |> Enum.into(%{})
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
