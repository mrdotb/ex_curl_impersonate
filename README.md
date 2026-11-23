# ExCurlImpersonate [![CI](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml/badge.svg)](https://github.com/mrdotb/ex_curl_impersonate/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/ex_curl_impersonate.svg)](https://hex.pm/packages/ex_curl_impersonate) [![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_curl_impersonate/)

Elixir bindings for [curl-impersonate](https://github.com/lexiforest/curl-impersonate) using Zig's C interoperability:
make HTTP requests with the TLS (JA3/JA4) and HTTP/2/HTTP/3 fingerprints of real browsers.

> [!NOTE]
> This is a fork of [ex_curl](https://github.com/danielrudn/ex_curl) by Daniel Rudnitski, adapted to link against
> [curl-impersonate](https://github.com/lexiforest/curl-impersonate)'s `libcurl-impersonate` instead of the system libcurl.
> On top of the original API it adds browser impersonation (`:impersonate`), HTTP version selection including HTTP/3
> (`:http_version`), every curl-impersonate fingerprint option, timeouts (`:timeout_ms`, `:connect_timeout_ms`),
> network binding and DNS control (`:interface`, `:ip_resolve`, `:resolve`), CA bundle paths (`:cainfo`, `:capath`) and
> transparent response decompression (`:accept_encoding`). Kerberos (`:http_auth_negotiate`) was removed because
> libcurl-impersonate is built without GSS-API.

## Installation

```elixir
def deps do
  [
    {:ex_curl_impersonate, "~> 0.2.0"}
  ]
end
```

Compiling requires [Zig 0.16](https://ziglang.org/download/) (or let Zigler fetch it). No system curl is needed: the pinned
`libcurl-impersonate` v2.3.2 release for your platform is downloaded at compile time, checksum-verified and shipped in
`priv/lib/` next to the NIF. On Linux x86_64 (glibc) the release comes from
[our fork](https://github.com/mrdotb/curl-impersonate), which adds the `chrome153`–`chrome157` targets (plus `_macos`
and `_linux` variants).

Zigler prefers its own toolchain in `~/.cache/zigler` and otherwise falls back to the first `zig` on your `PATH`. If an
older Zig is on `PATH` you will see errors like `build.zig.zon: error: expected string literal`; fix it by running
`mix zig.get` once (downloads Zig 0.16 into Zigler's cache) or `mise exec zig@0.16.0 -- mix compile`.

Supported platforms: Linux x86_64/aarch64 (glibc and musl), macOS arm64/x86_64 (CI runs on Linux x86_64 only).
For other platforms or offline builds, set `CURL_IMPERSONATE_DIR` to a directory containing `include/curl/curl.h` and
`libcurl-impersonate.so` (or `.dylib`).

The bundled library looks for CA certificates in `/etc/ssl/certs/ca-certificates.crt` (Linux) and `/etc/ssl/cert.pem`
(macOS). On distros that keep them elsewhere (RHEL, Amazon Linux, minimal containers) pass `:cainfo`, e.g.
`cainfo: "/etc/pki/tls/certs/ca-bundle.crt"` (or `:capath`).

### Building on one machine, running on another

The NIF is compiled for the CPU of the machine that builds it. If you build in CI or Docker and run elsewhere, a CPU
without the build machine's extensions (AVX-512, AVX2, ...) kills the VM as soon as the NIF loads:

- the release exits with code 132 (`SIGILL`, "illegal instruction") about a second after start, with nothing logged;
- the kernel log (`dmesg`) shows `invalid opcode ... in Elixir.ExCurlImpersonate.Request.so`.

Only the NIF built by Zigler is affected; the downloaded `libcurl-impersonate` is a portable build.

To build a NIF that runs on any CPU of the architecture, recompile this dependency with an explicit target. Zigler
reads `TARGET_ARCH`, `TARGET_OS` and `TARGET_ABI` and, when all three are set, compiles for the baseline CPU:

```dockerfile
RUN mix deps.compile
RUN NIF=_build/${MIX_ENV}/lib/ex_curl_impersonate/priv/lib/Elixir.ExCurlImpersonate.Request.so && \
    TARGET_ARCH=x86_64 TARGET_OS=linux TARGET_ABI=gnu mix deps.compile ex_curl_impersonate --force && \
    test -f "$NIF" && \
    ! objdump -d "$NIF" | grep -qE '%[yz]mm'
```

- Set the variables for this dependency only, not for the whole build: other packages (`vix`, `mjml`, `mdex`, ...)
  read the same `TARGET_*` variables to pick their precompiled binaries.
- Run it as a second step, after the normal `mix deps.compile`, so Zigler itself is already compiled.
- The last line checks the result: a baseline x86_64 build uses no `%ymm` or `%zmm` registers. `objdump` comes with
  `binutils`.
- Use `TARGET_ABI=musl` on Alpine. `TARGET_ARCH=aarch64` should work the same way but has not been tested.

## Usage

```elixir
ExCurlImpersonate.get("https://tls.peet.ws/api/all", impersonate: "chrome136")

# newest Chrome targets (Linux x86_64 glibc only): chrome153 to chrome157, plus _macos and _linux variants
ExCurlImpersonate.get("https://tls.peet.ws/api/all", impersonate: "chrome157_linux")

# HTTP/3
ExCurlImpersonate.get("https://cloudflare-quic.com/", impersonate: "chrome136", http_version: :http3_only)

# fine-tune the fingerprint
ExCurlImpersonate.get("https://example.com", impersonate: "chrome136", tls_grease: false, httpbaseheader: [])

# timeouts (milliseconds); without :timeout_ms a request can block forever
ExCurlImpersonate.get("https://example.com", timeout_ms: 10_000, connect_timeout_ms: 3_000)
# => {:error, "OPERATION_TIMEDOUT"} on expiry

# proxy, outgoing interface and DNS control
ExCurlImpersonate.get("https://example.com", proxy: "socks5://127.0.0.1:1080")
ExCurlImpersonate.get("https://example.com", interface: "eth1", ip_resolve: :v4)
ExCurlImpersonate.get("https://www.example.com", resolve: ["www.example.com:443:[2001:db8::1]"])
```

Response behaviour worth knowing:

- Compressed bodies (gzip, deflate, br, zstd) are decoded by default. Pass `accept_encoding: false` to get the raw
  bytes, or e.g. `accept_encoding: "gzip"` to limit the encodings.
- `headers` holds only the final response's headers (redirect hops and `1xx` responses are dropped). Repeated headers
  are joined with `", "`, except `set-cookie`, which is always a list.
- Cookies set during a redirect chain are sent on the following hops of that request; nothing is kept between requests.
- `http_version` reports the version actually used (`:http1_0`, `:http1_1`, `:http2` or `:http3`).

See the `ExCurlImpersonate` module docs for all options.

### IPv4 or IPv6 only

```elixir
# resolve names to IPv4 (or IPv6) addresses only: :v4, :v6 or :any (default)
ExCurlImpersonate.get("https://example.com", ip_resolve: :v6)

# or bind to a local address of the family you want
ExCurlImpersonate.get("https://example.com", interface: "2001:db8::10")
```

`:ip_resolve` applies to every name curl resolves, the proxy's included, so `ip_resolve: :v6` fails if the proxy is
only reachable over IPv4. To choose the address family of the target behind a proxy, pin the target's address with
`:resolve` and use a `socks5://` proxy (not `socks5h://`), so the proxy is asked to connect to that address:

```elixir
ExCurlImpersonate.get("https://www.example.com",
  proxy: "socks5://127.0.0.1:1080",
  resolve: ["www.example.com:443:[2001:db8::1]"]
)
```

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

