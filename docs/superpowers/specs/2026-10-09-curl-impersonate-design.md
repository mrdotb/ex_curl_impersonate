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

## Decisions

| Topic | Decision |
|---|---|
| Library source | Download pinned prebuilt release tarball at compile time, verify SHA-256, link the static `.a` |
| API surface | `:impersonate` + `:impersonate_default_headers` + every added `CURLOPT_*` as a typed snake_case option |
| Naming | Hex package `ex_curl_impersonate`, OTP app `:ex_curl_impersonate`, root module `ExCurlImpersonate`, repo `github.com/mrdotb/ex_curl_impersonate` |
| Kerberos | Removed (`:http_auth_negotiate`, kerberos tests, CI setup) — libcurl-impersonate is built without GSS-API/SPNEGO |
| Redirect history (`CURLINFO_REDIRECT_HISTORY`) | Out of scope |

## Non-goals

- HTTP/3 / QUIC enablement beyond exposing the options.
- Kerberos / SPNEGO.
- Windows, FreeBSD, Android, iOS targets.
- Shipping precompiled NIFs.

## Part 1 — Build & linking

### Pinned release

`mix.exs` (or a build module it reads) holds:

- `@curl_impersonate_version "2.2.3"`
- a map `target_triple => sha256` for the `libcurl-impersonate-v<ver>.<triple>.tar.gz`
  assets of these triples:
  `x86_64-linux-gnu`, `aarch64-linux-gnu`, `x86_64-linux-musl`,
  `aarch64-linux-musl`, `arm64-macos`, `x86_64-macos`.

### Fetch step — `ExCurlImpersonate.Build`

Runs before Zigler compiles the NIF (invoked at compile time from the module
that does `use Zig`, so the path is known when the `use` options are evaluated).

1. If `CURL_IMPERSONATE_DIR` is set, use it as-is (must contain `include/curl/curl.h`
   and `libcurl-impersonate.a`). Used for offline builds, Nix, unsupported platforms.
2. Otherwise detect the host triple from `:erlang.system_info(:system_architecture)`;
   on Linux, distinguish musl vs glibc (e.g. `ldd --version` output or presence of
   `/lib/ld-musl-*`).
3. Target dir: `_build/curl_impersonate/<version>/<triple>/`. If it already contains
   the `.a` and headers, skip.
4. Download the asset via `:httpc` (with `:ssl` + `:public_key` verification using
   OTP's `:public_key.cacerts_get/0`), verify SHA-256 against the pinned map, extract
   with `:erl_tar`.
5. Unknown triple and no env var → `Mix.raise` with a message naming the
   detected triple and the env-var escape hatch. Checksum mismatch → `Mix.raise`.

### Zigler configuration

Replace `c: [link_lib: {:system, "curl"}]` with include dir = `<dir>/include`,
link the static `<dir>/libcurl-impersonate.a`, and link libc++ (BoringSSL is C++;
verified: `zig cc v.c libcurl-impersonate.a -lc++` links and
`curl_easy_impersonate(h, "chrome136", 1)` returns `CURLE_OK`). Exact Zigler 0.16
option names for a static archive / libc++ are confirmed during implementation;
fallback is passing them as raw linker args.

Result: one self-contained NIF; no runtime dependency on system curl.

### Repo / CI changes

- `devenv.nix`: drop `pkgs.curl`.
- CI: drop `libcurl4-openssl-dev` and the Kerberos setup step + `--include kerberos:true`;
  keep ubuntu + macOS matrices; cache `_build/curl_impersonate`.
- Delete `test/kerberos_test.exs`, `test/support/files/setup_kerberos.sh`.
- README: new name, install instructions, supported platforms, `CURL_IMPERSONATE_DIR`,
  note that BoringSSL/curl/nghttp2/brotli/zstd/zlib/libidn2 (LGPL) are statically
  linked into the user-built NIF, with pointers to the bundled LICENSE files.
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
           impersonate: nil | binary, impersonate_default_headers: boolean},
  long_opts: %{tls_grease: nil | integer, ...},
  string_opts: %{http2_settings: nil | binary, ...},
  slist_opts: %{httpbaseheader: nil | [binary], ...}
}
```

Booleans in long opts are converted to `1`/`0` here.

### Zig side — `Request`

- `RequestFlags` gains `impersonate: ?[]u8`, `impersonate_default_headers: bool`,
  loses `http_auth_negotiate`.
- New structs `LongOpts` (fields `?i64`), `StringOpts` (`?[]u8`),
  `SlistOpts` (`?[][]u8`), added to `RequestConfiguration`.
- Comptime tables `long_opts`, `string_opts`, `slist_opts` of
  `.{ "field_name", cURL.CURLOPT_X }`, applied with `inline for`, setting only
  non-null fields — same pattern as existing `bool_flag_opts`.
- Order in `setCurlOpts`: `curl_easy_impersonate` first, then existing opts,
  then the three tables.
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

## Testing

- Existing test suite, renamed, minus Kerberos.
- Unit: `RequestConfiguration.build/3` option mapping (bool→long, nil defaults,
  no default user-agent when impersonating).
- Bypass: with `impersonate: "chrome136"`, request carries Chrome default headers
  (e.g. `sec-ch-ua`) and no `ex_curl_impersonate/...` user-agent; with
  `impersonate_default_headers: false`, those headers are absent; invalid target
  returns `{:error, _}`; an slist option and a string option round-trip without error.
- `@tag :external` (excluded by default): request `https://tls.peet.ws/api/all`
  with `impersonate: "chrome136"`, assert the reported HTTP/2 akamai fingerprint /
  JA4 matches Chrome's and differs from a non-impersonated request.
