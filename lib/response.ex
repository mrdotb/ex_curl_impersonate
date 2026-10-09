defmodule ExCurlImpersonate.Response do
  @moduledoc """
  A valid response returned by ExCurlImpersonate.

  ## Metrics

  When the `return_metrics` option is set to `true` for a request, the `metrics` field will be populated with a [`%ExCurlImpersonate.ResponseMetrics{}`](https://hexdocs.pm/ex_curl_impersonate/ExCurlImpersonate.ResponseMetrics.html) value.

  For example:

        iex> ExCurlImpersonate.get!("https://httpbin.org/get", return_metrics: true)
        %ExCurlImpersonate.Response{status_code: 200, metrics: %ExCurlImpersonate.ResponseMetrics{}, ...}

  """
  defstruct body: "",
            headers: %{},
            status_code: 200,
            metrics: nil

  @type t :: %__MODULE__{
          body: nil | String.t(),
          headers: map(),
          status_code: integer(),
          metrics: nil | ExCurlImpersonate.ResponseMetrics.t()
        }

  @doc false
  def parse(raw) do
    response = struct(__MODULE__, raw)

    %{
      response
      | headers: header_string_to_map(response.headers),
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

  defp parse_metrics(nil), do: nil

  defp parse_metrics(metrics) when is_map(metrics),
    do: struct(ExCurlImpersonate.ResponseMetrics, metrics)
end
