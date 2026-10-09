# ExCurlImpersonate [![CI](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml/badge.svg)](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/ex_curl_impersonate.svg)](https://hex.pm/packages/ex_curl_impersonate) [![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_curl_impersonate/)

Fork of [ex_curl](https://github.com/danielrudn/ex_curl) by Daniel Rudnitski.

Elixir bindings for libcurl using Zig's C interoperability.

## Installation

The package can be installed by adding `ex_curl_impersonate` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_curl_impersonate, "~> 0.1.0"}
  ]
end
```

To install `ex_curl_impersonate` in a Livebook, you can use `Mix.install/2`:

```elixir
Mix.install([
  {:ex_curl_impersonate, "~> 0.1.0"}
])
```

## Usage

```elixir
ExCurlImpersonate.get("https://httpbin.org/get")
# => {:ok, %ExCurlImpersonate.Response{status_code: 200, headers: %{"content-type" => "application/json", body: "{...}"}}}

# view request metrics
ExCurlImpersonate.get!("https://httpbin.org/get", return_metrics: true)
# => %ExCurlImpersonate.Response{status_code: 200, metrics: %ExCurlImpersonate.ResponseMetrics{total_time: 0.2, ...}, ...}}

# submit a form
ExCurlImpersonate.post("https://httpbin.org/post", body: "text=#{URI.encode_www_form("some value")}")
# => {:ok, %ExCurlImpersonate.Response{status_code: 200, body: "{...}"}}}
```

General usage examples and documentation can be found on the [ExCurlImpersonate module documentation page](https://hexdocs.pm/ex_curl_impersonate/ExCurlImpersonate.html).

### HTTP Clients and Shared Defaults

```elixir
# create clients and set default options
defmodule CustomClient do
  use ExCurlImpersonate.Client, defaults: [headers: %{"User-Agent" => "custom-user-agent"}]
end

# all requests using CustomClient will use the custom User-Agent header
CustomClient.get("https://httpbin.org/get")
# => {:ok, %ExCurlImpersonate.Response{status_code: 200, body: ".."}}
```

You can `use ExCurlImpersonate.Client` on any module to create HTTP Clients.
Below is an example of a GitHub API client based on the great [Tesla documentation](https://hexdocs.pm/tesla/readme.html):

```elixir
defmodule GitHubClient do
  use ExCurlImpersonate.Client, defaults: [base_url: "https://api.github.com"]

  def user_repos(username), do: get("/users/#{username}/repos")
end

# we can now call the GitHubClient with the pre-defined HTTP verb functions:
GitHubClient.get("/users/danielrudn/repos")
# => {:ok, %ExCurlImpersonate.Response{status_code: 200, body: "{....}"}}

# or call our custom defined functions:
GitHubClient.user_repos("danielrudn")
# => {:ok, %ExCurlImpersonate.Response{status_code: 200, body: "{....}"}}
```

More examples and details on using `ExCurlImpersonate.Client` are available on the [ExCurlImpersonate.Client module documentation page](https://hexdocs.pm/ex_curl_impersonate/ExCurlImpersonate.Client.html).

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ex_curl_impersonate>.

## Acknowledgements

This library is built on top of [libcurl](https://curl.se/libcurl/) as a NIF using [Zigler](https://github.com/ityonemo/zigler) and [Zig's C interoperability](https://ziglang.org/learn/samples/#using-curl-from-zig).

Inspired by [Tesla](https://github.com/elixir-tesla/tesla), [Katipo](https://github.com/puzza007/katipo), and [Req](https://github.com/wojtekmach/req).

