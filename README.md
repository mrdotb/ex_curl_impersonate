# ExCurlImpersonate [![CI](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml/badge.svg)](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/ex_curl_impersonate.svg)](https://hex.pm/packages/ex_curl_impersonate) [![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_curl_impersonate/)

Elixir bindings for [curl-impersonate](https://github.com/lexiforest/curl-impersonate) using Zig's C interoperability:
make HTTP requests with the TLS (JA3/JA4) and HTTP/2/HTTP/3 fingerprints of real browsers.

> [!NOTE]
> This is a fork of [ex_curl](https://github.com/danielrudn/ex_curl) by Daniel Rudnitski, adapted to link against
> [curl-impersonate](https://github.com/lexiforest/curl-impersonate)'s `libcurl-impersonate` instead of the system libcurl.
> On top of the original API it adds browser impersonation (`:impersonate`), HTTP version selection including HTTP/3
> (`:http_version`) and every curl-impersonate fingerprint option. Kerberos (`:http_auth_negotiate`) was removed because
> libcurl-impersonate is built without GSS-API.

## Installation

```elixir
def deps do
  [
    {:ex_curl_impersonate, "~> 0.1.0"}
  ]
end
```

Compiling requires [Zig 0.16](https://ziglang.org/download/) (or let Zigler fetch it). No system curl is needed: the pinned
`libcurl-impersonate` v2.2.3 release for your platform is downloaded at compile time, checksum-verified and shipped in
`priv/lib/` next to the NIF.

Zigler prefers its own toolchain in `~/.cache/zigler` and otherwise falls back to the first `zig` on your `PATH`. If an
older Zig is on `PATH` you will see errors like `build.zig.zon: error: expected string literal`; fix it by running
`mix zig.get` once (downloads Zig 0.16 into Zigler's cache) or `mise exec zig@0.16.0 -- mix compile`.

Supported platforms: Linux x86_64/aarch64 (glibc and musl), macOS arm64/x86_64.
For other platforms or offline builds, set `CURL_IMPERSONATE_DIR` to a directory containing `include/curl/curl.h` and
`libcurl-impersonate.so` (or `.dylib`).

The bundled library looks for CA certificates in `/etc/ssl/certs/ca-certificates.crt` (Linux) and `/etc/ssl/cert.pem`
(macOS). On distros that keep them elsewhere (RHEL, Amazon Linux, minimal containers) pass `:cainfo`, e.g.
`cainfo: "/etc/pki/tls/certs/ca-bundle.crt"` (or `:capath`).

## Usage

```elixir
ExCurlImpersonate.get("https://tls.peet.ws/api/all", impersonate: "chrome136")

# HTTP/3
ExCurlImpersonate.get("https://cloudflare-quic.com/", impersonate: "chrome136", http_version: :http3_only)

# fine-tune the fingerprint
ExCurlImpersonate.get("https://example.com", impersonate: "chrome136", tls_grease: false, httpbaseheader: [])
```

See the `ExCurlImpersonate` module docs for all options.

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

## Licensing

This package is MIT licensed. The downloaded `libcurl-impersonate` bundles curl, BoringSSL, nghttp2, nghttp3, ngtcp2,
brotli, zstd, zlib and libidn2 (LGPL-3.0/GPL-2.0); their license notices ship in
`priv/lib/curl-impersonate-licenses/`.

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ex_curl_impersonate>.

## Acknowledgements

This library is built on top of [curl-impersonate](https://github.com/lexiforest/curl-impersonate) as a NIF using [Zigler](https://github.com/ityonemo/zigler) and [Zig's C interoperability](https://ziglang.org/learn/samples/#using-curl-from-zig).

Inspired by [Tesla](https://github.com/elixir-tesla/tesla), [Katipo](https://github.com/puzza007/katipo), and [Req](https://github.com/wojtekmach/req).

