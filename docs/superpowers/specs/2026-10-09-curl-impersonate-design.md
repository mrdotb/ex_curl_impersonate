# ex_curl_impersonate — design

Date: 2026-10-09

## Goal

Fork `ex_curl` into `ex_curl_impersonate`: Elixir bindings that link against
[lexiforest/curl-impersonate](https://github.com/lexiforest/curl-impersonate)'s
`libcurl-impersonate` instead of system libcurl, so requests can reproduce real
browser TLS (JA3/JA4) and HTTP/2 fingerprints. All existing ex_curl behaviour
keeps working, except Kerberos (see Non-goals).

Success criteria:

- `mix compile` on a supported platform needs only Elixir/OTP + Zig; no system curl.
- `ExCurlImpersonate.get(url, impersonate: "chrome136")` produces a Chrome
  fingerprint as reported by a TLS echo service.
- Every curl-impersonate `CURLOPT_*` addition is settable as a keyword option.
- `http_version: :http3_only` completes a request over HTTP/3 (QUIC).

## Decisions

| Topic | Decision |
|---|---|
| Library source | Download pinned prebuilt release tarball at compile time, verify SHA-256, link the shared library dynamically; ship it in `priv/lib` next to the NIF, found via `$ORIGIN` / `@loader_path` rpath |
| Toolchain | `mise.toml` pins erlang 29.1.1, elixir 1.20.4-otp-29, zig 0.16.0 |
| API surface | `:impersonate` + `:impersonate_default_headers` + every added `CURLOPT_*` as a typed snake_case option |
| Naming | Hex package `ex_curl_impersonate`, OTP app `:ex_curl_impersonate`, root module `ExCurlImpersonate`, repo `github.com/mrdotb/ex_curl_impersonate` |
| Kerberos | Removed (`:http_auth_negotiate`, kerberos tests, CI setup) — libcurl-impersonate is built without GSS-API/SPNEGO |
| HTTP version / HTTP/3 | New `:http_version` option (maps to `CURLOPT_HTTP_VERSION`); `Response.http_version` from `CURLINFO_HTTP_VERSION`. Verified: v2.2.3 is built with ngtcp2/nghttp3 and negotiates HTTP/3 with `chrome136` + `CURL_HTTP_VERSION_3ONLY` |
| Redirect history (`CURLINFO_REDIRECT_HISTORY`) | Out of scope |

## Non-goals

- Kerberos / SPNEGO.
- Windows, FreeBSD, Android, iOS targets.
- Shipping precompiled NIFs.

## Part 1 — Build & linking

### Why dynamic, not static

Linking the 64 MB `libcurl-impersonate.a` crashes Zig 0.16's default Debug
toolchain (self-hosted backend/linker SEGV, reproduced with a 2-line Zig program;
`-fllvm -flld` or ReleaseSafe link fine). Zigler 0.16 always runs a Debug "sema"
build that links every `link_lib`, and has no option to force LLVM. Linking the
shared library works. Verified end to end: NIF built with
`link_lib: "<dir>/libcurl-impersonate.so"` + `rpaths: [{:special, "$ORIGIN"}]`
has `NEEDED libcurl-impersonate.so.4`, `RUNPATH $ORIGIN`, and performs real
requests once `libcurl-impersonate.so.4` sits next to it in `priv/lib/`.

### Pinned release

`ExCurlImpersonate.Build` holds:

- `@version "2.2.3"`
- `@checksums` (SHA-256 of `libcurl-impersonate-v2.2.3.<triple>.tar.gz`, from the
  GitHub release asset digests):

| triple | sha256 |
|---|---|
| `x86_64-linux-gnu` | `d5eb746c109be4d945cc5fcbe8a5c4940471041be4901439d50111cc3c83359d` |
| `aarch64-linux-gnu` | `4718401d263208866769825e97ea5f2ae20bfc3e991e617c3c85408df821475a` |
| `x86_64-linux-musl` | `46333ccae3ea5865e27bf11d1a8f30a9f3563cb5aab7ec4aec9b52a3f7d401b5` |
| `aarch64-linux-musl` | `3c7104315f853268e6b289f64627fdf7df1a466a8a8d4da2d313c182dcbc0d34` |
| `arm64-macos` | `16a73c8dfc55cb8c2354f93f43525529d0df6cbfc484fb7a4357b3891f9dbb6a` |
| `x86_64-macos` | `32634096e31e879d0a193f87e4a4083e2eb44b9b9318eb5b32f85f495104a049` |

Shared-library file names inside the tarballs:

| OS | real file | soname / install name (what the NIF records) |
|---|---|---|
| Linux | `libcurl-impersonate.so.4.8.0` | `libcurl-impersonate.so.4` |
| macOS | `libcurl-impersonate.4.8.0.dylib` | `@rpath/libcurl-impersonate.4.dylib` |

### Fetch step — `ExCurlImpersonate.Build`

Called at compile time from the module that does `use Zig` (its return value
feeds the `use Zig` options).

1. If `CURL_IMPERSONATE_DIR` is set, use it as-is (must contain `include/curl/curl.h`
   and the shared library). Used for offline builds, Nix, unsupported platforms.
2. Otherwise detect the host triple from `:erlang.system_info(:system_architecture)`;
   on Linux, musl vs glibc by checking for `/lib/ld-musl-*`.
3. Cache dir: `Path.join(Mix.Project.build_path(), "curl_impersonate/<version>/<triple>")`.
   Skip download if it already holds the headers and shared library.
4. Download via `:httpc` (TLS verification with `:public_key.cacerts_get/0`),
   verify SHA-256, extract with `:erl_tar`.
5. Copy the real shared library into `Path.join(Mix.Project.app_path(), "priv/lib")`
   under its soname file name (`libcurl-impersonate.so.4` /
   `libcurl-impersonate.4.dylib`) — this is where Zigler writes the NIF, so it ends
   up in releases too.
6. Unknown triple and no env var → `Mix.raise` naming the detected triple and the
   env-var escape hatch. Checksum mismatch → `Mix.raise`.

Returns `%{include_dir: ..., link_lib: ...}` for the Zigler config.

### Zigler configuration

```elixir
c: [
  include_dirs: lib.include_dir,
  link_lib: lib.link_lib,            # path to the shared library in the cache dir
  rpaths: [{:special, "$ORIGIN"}]    # "@loader_path" on macOS
]
```

Result: NIF + `libcurl-impersonate` side by side in `priv/lib/`; no dependency on
system curl.

### Repo / CI changes

- `devenv.nix`: drop `pkgs.curl`. Add `mise.toml` (see Toolchain).
- CI: drop `libcurl4-openssl-dev` and the Kerberos setup step + `--include kerberos:true`;
  keep ubuntu + macOS matrices; cache `_build/<env>/curl_impersonate`.
- Delete `test/kerberos_test.exs`, `test/support/files/setup_kerberos.sh`.
- README: new name, install instructions, supported platforms, `CURL_IMPERSONATE_DIR`,
  note that the downloaded `libcurl-impersonate` (bundling BoringSSL, curl, nghttp2/3,
  ngtcp2, brotli, zstd, zlib, libidn2 (LGPL)) is shipped in `priv/lib`, with pointers
  to the LICENSE files in the release tarball.
- `package/0`: new name, description, links, maintainers; keep MIT and credit upstream ex_curl.

## Part 2 — API & Zig side

### Rename

`ExCurl` → `ExCurlImpersonate` across all modules (`Client`, `Request`,
`RequestConfiguration`, `Response`, `ResponseMetrics`, `CurlError`, `CurlErrorCodes`),
tests, doctests, README.

### Options

Existing options unchanged except `:http_auth_negotiate` (removed).

New:

- `:impersonate` — browser target string (e.g. `"chrome136"`, `"safari18_0"`,
  `"firefox135"`), default `nil`. Applied via
  `curl_easy_impersonate(handle, target, default_headers)` **before** all other
  options, so explicit options override the preset. Non-OK return →
  `{:error, <curl error name>}`.
- `:impersonate_default_headers` — boolean, default `true`.
- `:http_version` — one of `:http1_0`, `:http1_1`, `:http2`, `:http2_tls`,
  `:http2_prior_knowledge`, `:http3` (attempt, fall back), `:http3_only`;
  default `nil` (leave curl's default / the impersonate preset untouched).
  Mapped in Elixir to the `CURL_HTTP_VERSION_*` value and passed to Zig as a
  `?i64` flag; applied after `curl_easy_impersonate` so it overrides the preset.
  Unknown atom → `ArgumentError` in `RequestConfiguration.build/3`.
- When `:impersonate` is set, the implicit `user-agent: ex_curl_impersonate/<ver>`
  header is **not** added (user-supplied headers are still sent).

Fingerprint options (all default `nil` = not set). Name = lowercase of the
`CURLOPT_` suffix.

Long (Elixir integer or boolean; booleans converted to 1/0 in Elixir):
`http2_no_priority`, `http2_window_update`, `http3_ssl_permute_extensions`,
`proxy_credential_no_reuse`, `quic_initial_packet_number`, `split_cookies`,
`ssl_enable_alps`, `ssl_enable_ticket`, `ssl_permute_extensions`,
`stream_exclusive`, `tls_grease`, `tls_key_shares_limit`, `tls_key_usage_no_check`,
`tls_record_size_limit`, `tls_signed_cert_timestamps`, `tls_status_request`,
`tls_use_new_alps_codepoint`, `ws_ssl_disable_ticket`.

String:
`form_boundary`, `http2_pseudo_headers_order`, `http2_settings`, `http2_streams`,
`http3_httpheader_order`, `http3_pseudo_headers_order`, `http3_settings`,
`http3_sig_hash_algs`, `http3_ssl_ec_curves`, `http3_tls_extension_order`,
`httpheader_order`, `quic_cid_length`, `quic_transport_parameters`,
`ssl_cert_compression`, `ssl_sig_hash_algs`, `tls_delegated_credentials`,
`tls_extension_order`, `tls_trust_anchors`, `ws_httpheader_order`,
`ws_ssl_cert_compression`.

String list (list of `"Name: value"` strings):
`httpbaseheader`, `http3_httpheader`, `ws_httpheader`.

(`CURLOPT_IMPERSONATE` itself is not exposed; `:impersonate` uses
`curl_easy_impersonate` instead.)

### Elixir side — `RequestConfiguration`

Holds three module-attribute lists (`@long_opts`, `@string_opts`, `@slist_opts`)
of the atoms above. `build/3` produces:

```elixir
%{
  ...,
  flags: %{...existing minus http_auth_negotiate...,
           impersonate: nil | binary, impersonate_default_headers: boolean,
           http_version: nil | integer},
  long_opts: %{tls_grease: nil | integer, ...},
  string_opts: %{http2_settings: nil | binary, ...},
  slist_opts: %{httpbaseheader: nil | [binary], ...}
}
```

Booleans in long opts are converted to `1`/`0` here.

### Zig side — `Request`

- `RequestFlags` gains `impersonate: ?[]u8`, `impersonate_default_headers: bool`,
  `http_version: ?i64`, loses `http_auth_negotiate`.
- `Response` gains `http_version: i64` read via `CURLINFO_HTTP_VERSION`;
  Elixir `Response` exposes it as an atom (`:http1_0`, `:http1_1`, `:http2`,
  `:http3`, or `nil` for 0/unknown).
- New structs `LongOpts` (fields `?i64`), `StringOpts` (`?[]u8`),
  `SlistOpts` (`?[][]u8`), added to `RequestConfiguration`.
- Comptime tables `long_opts`, `string_opts`, `slist_opts` of
  `.{ "field_name", cURL.CURLOPT_X }`, applied with `inline for`, setting only
  non-null fields — same pattern as existing `bool_flag_opts`.
- Order in `setCurlOpts`: `curl_easy_impersonate` first, then existing opts
  (including `http_version`), then the three tables.
- slist values are built with `curl_slist_append` and freed with
  `curl_slist_free_all` after `curl_easy_perform` (lifetimes must cover perform).
- Failures from impersonate / new setopts return `beam.make_error_pair(code)`,
  not `unreachable`.
- `@cInclude("curl/curl.h")` resolves to the curl-impersonate header via the
  include dir.

### Error handling summary

| Case | Result |
|---|---|
| Unknown impersonate target | `{:error, "<CURLE name>"}` from curl's return code |
| setopt rejects a new option value | `{:error, "<CURLE name>"}` |
| Unsupported build platform w/o env var | compile-time `Mix.raise` |
| Download / checksum failure | compile-time `Mix.raise` |
| Shared library missing at load time | NIF `:on_load` fails with the dlopen error (only possible if `priv/lib` was tampered with) |

## Testing

- Existing test suite, renamed, minus Kerberos.
- Unit: `RequestConfiguration.build/3` option mapping (bool→long, nil defaults,
  no default user-agent when impersonating, `:http_version` atom→value,
  invalid `:http_version` raises).
- Bypass: plain request reports `response.http_version == :http1_1`.
- Bypass: with `impersonate: "chrome136"`, request carries Chrome default headers
  (e.g. `sec-ch-ua`) and no `ex_curl_impersonate/...` user-agent; with
  `impersonate_default_headers: false`, those headers are absent; invalid target
  returns `{:error, _}`; an slist option and a string option round-trip without error.
- `@tag :external` (excluded by default): request `https://tls.peet.ws/api/all`
  with `impersonate: "chrome136"`, assert the reported HTTP/2 akamai fingerprint /
  JA4 matches Chrome's and differs from a non-impersonated request.
- `@tag :external`: request `https://cloudflare-quic.com/` with
  `impersonate: "chrome136", http_version: :http3_only`, assert
  `{:ok, %{http_version: :http3}}`.
