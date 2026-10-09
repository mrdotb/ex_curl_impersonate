# ex_curl_impersonate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `ex_curl` into `ex_curl_impersonate`: Elixir bindings linked against lexiforest's prebuilt `libcurl-impersonate`, exposing browser impersonation, every curl-impersonate `CURLOPT_*`, and HTTP version selection (incl. HTTP/3).

**Architecture:** A compile-time build script (`build/curl_impersonate.ex`, loaded with `Code.require_file` from `lib/request.ex`) downloads + checksums the pinned release for the host, copies the shared library into the app's `priv/lib/`, and returns Zigler `c:` options (include dir, link the `.so`/`.dylib`, `$ORIGIN`/`@loader_path` rpath). The Zig NIF gains impersonation, `http_version`, and three comptime option tables (long / string / slist) mirrored by three option lists in `RequestConfiguration`.

**Tech Stack:** Elixir 1.20.4 / OTP 29.1.1, Zig 0.16.0, Zigler 0.16.0, libcurl-impersonate v2.2.3, Bypass for tests. Toolchain via `mise.toml` (already committed).

**Spec:** `docs/superpowers/specs/2026-10-09-curl-impersonate-design.md`

## Global Constraints

- Run every `mix`/`zig` command through mise: `mise exec -- mix ...` (the repo's `mise.toml` pins erlang 29.1.1, elixir 1.20.4-otp-29, zig 0.16.0). Never edit `~/.mise.toml`.
- Hex package `ex_curl_impersonate`, OTP app `:ex_curl_impersonate`, root module `ExCurlImpersonate`, repo `https://github.com/mrdotb/ex_curl_impersonate`. Version `0.1.0`.
- curl-impersonate version `2.2.3`; supported triples: `x86_64-linux-gnu`, `aarch64-linux-gnu`, `x86_64-linux-musl`, `aarch64-linux-musl`, `arm64-macos`, `x86_64-macos`.
- Link **dynamically** (static `.a` segfaults Zig 0.16's Debug linker — see spec). Library lives in `priv/lib/` next to the NIF as `libcurl-impersonate.so.4` (Linux) / `libcurl-impersonate.4.dylib` (macOS).
- `CURL_IMPERSONATE_DIR` env var overrides the download (dir with `include/curl/curl.h` + `libcurl-impersonate.so` or `libcurl-impersonate.dylib`).
- `:http_auth_negotiate` and Kerberos support are removed.
- Option names = lowercase of the `CURLOPT_` suffix; all new options default to `nil` (= not set).
- Keep `mix format --check-formatted` and `mix compile --warnings-as-errors` clean.
- Commits end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. Long option given `false` → must send `0` (explicitly disable), not be treated as unset. Test in Task 4.
2. User-supplied `user-agent` header together with `impersonate:` → the user's value wins over the browser preset. Test in Task 3.
3. Wrong value type (e.g. `tls_grease: "yes"`, `http2_settings: 1`, `httpbaseheader: "x"`, `http_version: :http4`) → `ArgumentError` from Elixir with the option name, never a NIF crash. Tests in Tasks 3 and 4.
4. Empty list for an slist option (`httpbaseheader: []`) → sets NULL, which removes the impersonate default headers. Test in Task 4.
5. Compiled as a dependency of another project / inside a `mix release` → `priv/lib/libcurl-impersonate.*` must sit next to the NIF in *that* app's build dir. Manual verification step in Task 2.

## File Structure

| File | Responsibility |
|---|---|
| `build/curl_impersonate.ex` (new) | `ExCurlImpersonate.Build`: host triple, download, checksum, extract, copy to priv, Zigler `c:` opts |
| `lib/request.ex` | Zig NIF: curl setup, impersonate, http_version, option tables, response |
| `lib/request_configuration.ex` | Elixir option parsing/validation → struct marshalled to Zig |
| `lib/response.ex` | Parse raw NIF response; map `http_version` int → atom |
| `lib/ex_curl_impersonate.ex` (renamed from `lib/ex_curl.ex`) | Public API + option docs |
| `lib/client.ex`, `lib/curl_error*.ex`, `lib/response_metrics.ex` | Renamed only |
| `test/build_test.exs` (new) | Unit tests for `ExCurlImpersonate.Build` pure functions |
| `test/request_configuration_test.exs` (new) | Option mapping/validation unit tests |
| `test/impersonate_test.exs` (new) | Bypass tests for impersonate, http_version, fingerprint opts |
| `test/external_test.exs` (new) | `@tag :external` network tests (TLS fingerprint, HTTP/3) |

---

### Task 1: Rename to ExCurlImpersonate and drop Kerberos

Still linked against system curl; purely mechanical, so the existing suite is the test.

**Files:**
- Move: `lib/ex_curl.ex` → `lib/ex_curl_impersonate.ex`, `test/ex_curl_test.exs` → `test/ex_curl_impersonate_test.exs`
- Modify: every file under `lib/`, `test/`, plus `mix.exs`, `README.md`, `.gitignore`
- Delete: `test/kerberos_test.exs`, `test/support/files/setup_kerberos.sh`

**Interfaces:**
- Produces: modules `ExCurlImpersonate`, `ExCurlImpersonate.{Client, Request, RequestConfiguration, Response, ResponseMetrics, CurlError, CurlErrorCodes, TestClient}`; app `:ex_curl_impersonate`; default UA `"ex_curl_impersonate/0.1.0"`.

- [ ] **Step 1: Move files and delete Kerberos**

```bash
git mv lib/ex_curl.ex lib/ex_curl_impersonate.ex
git mv test/ex_curl_test.exs test/ex_curl_impersonate_test.exs
git rm -q test/kerberos_test.exs test/support/files/setup_kerberos.sh
```

- [ ] **Step 2: Mechanical rename**

```bash
grep -rlE 'ExCurl|ex_curl' lib test mix.exs README.md .gitignore \
  | xargs sed -i -e 's/ExCurl/ExCurlImpersonate/g' -e 's/ex_curl/ex_curl_impersonate/g'
grep -rn 'ex_curl_impersonate/0.4.0' lib README.md | cut -d: -f1 | sort -u \
  | xargs sed -i 's#ex_curl_impersonate/0.4.0#ex_curl_impersonate/0.1.0#g'
```

Then fix by hand:
- `mix.exs`: `version: "0.1.0"`, `@source_url "https://github.com/mrdotb/ex_curl_impersonate"`, `package/0` → `description: "Elixir bindings for libcurl-impersonate (browser TLS/HTTP2 fingerprint impersonation)."`, `maintainers: ["mrdotb"]`, `files: ~w(lib build mix.exs README.md LICENSE .formatter.exs)` (the `build` dir is added in Task 2; listing it now is harmless).
- `README.md`: the badges/links that now point to `danielrudn/ex_curl_impersonate` → `mrdotb/ex_curl_impersonate`; `{:ex_curl_impersonate, "~> 0.4.0"}` → `"~> 0.1.0"`; add under the title: `Fork of [ex_curl](https://github.com/danielrudn/ex_curl) by Daniel Rudnitski.`; the GitHub example `GitHubClient.get("/users/danielrudn/repos")` lines stay as-is (they reference a real GitHub user, unrelated to the rename).
- `lib/ex_curl_impersonate.ex` moduledoc: delete the `:http_auth_negotiate` bullet.
- `lib/request_configuration.ex`: delete `http_auth_negotiate: Keyword.get(opts, :http_auth_negotiate, false),`.
- `lib/request.ex`: delete `http_auth_negotiate: bool,` from `RequestFlags` and the whole `if (config.flags.http_auth_negotiate) { ... }` block in `setCurlOpts`.
- `test/test_helper.exs`: `ExUnit.configure(exclude: [external: true])`.

- [ ] **Step 3: Check nothing old remains**

Run: `grep -rnE 'ExCurl[^I]|\bex_curl\b|negotiate|kerberos' lib test mix.exs README.md`
Expected: only the upstream credit line / `danielrudn/repos` examples in README.

- [ ] **Step 4: Run the suite**

Run: `mise exec -- mix deps.get && mise exec -- mix format && mise exec -- mix test`
Expected: PASS (same count as before minus the kerberos tests; doctests that hit the network may need connectivity, as before).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename to ExCurlImpersonate and drop kerberos support

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Download and link libcurl-impersonate

**Files:**
- Create: `build/curl_impersonate.ex`
- Create: `test/build_test.exs`
- Modify: `lib/request.ex` (top of module), `lib/ex_curl_impersonate.ex` (add `curl_version/0`), `test/test_helper.exs`, `devenv.nix`, `.github/workflows/ci.yml`, `.github/workflows/publish.yml`

**Interfaces:**
- Produces:
  - `ExCurlImpersonate.Build.zig_c_opts() :: keyword()` — called in `use Zig, c: ...`
  - `ExCurlImpersonate.Build.triple(sysarch :: String.t()) :: String.t() | nil`
  - `ExCurlImpersonate.Build.verify_checksum!(binary, expected_hex :: String.t()) :: :ok`
  - `ExCurlImpersonate.Build.layout(os :: :linux | :macos) :: %{link_name: String.t(), soname: String.t(), rpath: String.t()}`
  - NIF `ExCurlImpersonate.Request.curl_version() :: String.t()` and public `ExCurlImpersonate.curl_version/0`

- [ ] **Step 1: Write failing unit tests**

`test/build_test.exs`:

```elixir
defmodule ExCurlImpersonate.BuildTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.Build

  describe "triple/1" do
    test "maps OTP system architectures to release triples" do
      assert Build.triple("x86_64-pc-linux-gnu") == "x86_64-linux-gnu"
      assert Build.triple("aarch64-unknown-linux-gnu") == "aarch64-linux-gnu"
      assert Build.triple("x86_64-pc-linux-musl") == "x86_64-linux-musl"
      assert Build.triple("aarch64-alpine-linux-musl") == "aarch64-linux-musl"
      assert Build.triple("aarch64-apple-darwin23.4.0") == "arm64-macos"
      assert Build.triple("x86_64-apple-darwin22.1.0") == "x86_64-macos"
    end

    test "returns nil for unsupported platforms" do
      assert Build.triple("win32") == nil
      assert Build.triple("x86_64-unknown-freebsd14.0") == nil
      assert Build.triple("riscv64-unknown-linux-gnu") == nil
    end
  end

  describe "verify_checksum!/2" do
    test "accepts a matching sha256" do
      assert Build.verify_checksum!("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == :ok
    end

    test "raises on mismatch" do
      assert_raise Mix.Error, ~r/checksum mismatch/, fn ->
        Build.verify_checksum!("abc", String.duplicate("0", 64))
      end
    end
  end

  test "layout/1 names the shared library per OS" do
    assert Build.layout(:linux) ==
             %{link_name: "libcurl-impersonate.so", soname: "libcurl-impersonate.so.4", rpath: "$ORIGIN"}

    assert Build.layout(:macos) ==
             %{link_name: "libcurl-impersonate.dylib", soname: "libcurl-impersonate.4.dylib", rpath: "@loader_path"}
  end

  test "has a checksum for every supported triple" do
    for t <- ~w(x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl aarch64-linux-musl arm64-macos x86_64-macos) do
      assert Build.checksum(t) =~ ~r/^[0-9a-f]{64}$/
    end
  end
end
```

`test/test_helper.exs` (build script is not in `lib/`, so load it for tests):

```elixir
Code.require_file("../build/curl_impersonate.ex", __DIR__)
ExUnit.configure(exclude: [external: true])
ExUnit.start()
```

Add to `test/ex_curl_impersonate_test.exs`:

```elixir
  test "is linked against libcurl-impersonate" do
    assert ExCurlImpersonate.curl_version() =~ "IMPERSONATE"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mise exec -- mix test test/build_test.exs`
Expected: FAIL — `build/curl_impersonate.ex` does not exist.

- [ ] **Step 3: Implement the build script**

`build/curl_impersonate.ex`:

```elixir
defmodule ExCurlImpersonate.Build do
  @moduledoc false
  # Compile-time helper: fetches the pinned libcurl-impersonate release for the
  # host, installs the shared library next to the NIF and returns the Zigler
  # `c:` options. Loaded via Code.require_file from lib/request.ex.

  @version "2.2.3"
  @base_url "https://github.com/lexiforest/curl-impersonate/releases/download"
  @checksums %{
    "x86_64-linux-gnu" => "d5eb746c109be4d945cc5fcbe8a5c4940471041be4901439d50111cc3c83359d",
    "aarch64-linux-gnu" => "4718401d263208866769825e97ea5f2ae20bfc3e991e617c3c85408df821475a",
    "x86_64-linux-musl" => "46333ccae3ea5865e27bf11d1a8f30a9f3563cb5aab7ec4aec9b52a3f7d401b5",
    "aarch64-linux-musl" => "3c7104315f853268e6b289f64627fdf7df1a466a8a8d4da2d313c182dcbc0d34",
    "arm64-macos" => "16a73c8dfc55cb8c2354f93f43525529d0df6cbfc484fb7a4357b3891f9dbb6a",
    "x86_64-macos" => "32634096e31e879d0a193f87e4a4083e2eb44b9b9318eb5b32f85f495104a049"
  }

  def version, do: @version
  def checksum(triple), do: Map.fetch!(@checksums, triple)

  def zig_c_opts do
    os = host_os()
    %{link_name: link_name, soname: soname, rpath: rpath} = layout(os)
    dir = lib_dir!()
    install!(Path.join(dir, link_name), soname)

    [
      include_dirs: Path.join(dir, "include"),
      link_lib: Path.join(dir, link_name),
      rpaths: [{:special, rpath}]
    ]
  end

  def layout(:linux),
    do: %{link_name: "libcurl-impersonate.so", soname: "libcurl-impersonate.so.4", rpath: "$ORIGIN"}

  def layout(:macos),
    do: %{link_name: "libcurl-impersonate.dylib", soname: "libcurl-impersonate.4.dylib", rpath: "@loader_path"}

  def triple(sysarch) do
    case String.split(sysarch, "-") do
      ["x86_64", _, "linux", "gnu" <> _] -> "x86_64-linux-gnu"
      ["aarch64", _, "linux", "gnu" <> _] -> "aarch64-linux-gnu"
      ["x86_64", _, "linux", "musl" <> _] -> "x86_64-linux-musl"
      ["aarch64", _, "linux", "musl" <> _] -> "aarch64-linux-musl"
      ["aarch64", "apple", "darwin" <> _] -> "arm64-macos"
      ["x86_64", "apple", "darwin" <> _] -> "x86_64-macos"
      _ -> nil
    end
  end

  def verify_checksum!(data, expected) do
    actual = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

    if actual == expected do
      :ok
    else
      Mix.raise("libcurl-impersonate checksum mismatch: expected #{expected}, got #{actual}")
    end
  end

  defp sysarch, do: List.to_string(:erlang.system_info(:system_architecture))

  defp host_os do
    if String.contains?(sysarch(), "darwin"), do: :macos, else: :linux
  end

  defp lib_dir! do
    case System.get_env("CURL_IMPERSONATE_DIR") do
      nil -> fetch!()
      dir -> Path.expand(dir)
    end
  end

  defp fetch! do
    triple =
      triple(sysarch()) ||
        Mix.raise("""
        libcurl-impersonate has no prebuilt release for #{sysarch()}.
        Set CURL_IMPERSONATE_DIR to a directory containing include/curl/curl.h
        and libcurl-impersonate.so (or .dylib).
        """)

    dir = Path.join([Mix.Project.build_path(), "curl_impersonate", @version, triple])

    unless File.exists?(Path.join(dir, "include/curl/curl.h")) do
      asset = "libcurl-impersonate-v#{@version}.#{triple}.tar.gz"
      Mix.shell().info("Downloading #{asset}")
      data = download!("#{@base_url}/v#{@version}/#{asset}")
      verify_checksum!(data, checksum(triple))

      tmp = dir <> ".tmp"
      File.rm_rf!(tmp)
      File.mkdir_p!(tmp)
      :ok = :erl_tar.extract({:binary, data}, [:compressed, cwd: String.to_charlist(tmp)])
      File.rm_rf!(dir)
      File.rename!(tmp, dir)
    end

    dir
  end

  defp download!(url) do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> body
      other -> Mix.raise("Failed to download #{url}: #{inspect(other)}")
    end
  end

  # Copy (following symlinks) into the dir Zigler writes the NIF to, under the
  # soname the NIF records as NEEDED, so the rpath finds it at load time.
  defp install!(lib_path, soname) do
    File.exists?(lib_path) || Mix.raise("libcurl-impersonate not found at #{lib_path}")
    priv_lib = Path.join(Mix.Project.app_path(), "priv/lib")
    File.mkdir_p!(priv_lib)
    File.cp!(lib_path, Path.join(priv_lib, soname))
  end
end
```

- [ ] **Step 4: Wire into the NIF**

`lib/request.ex` top:

```elixir
defmodule ExCurlImpersonate.Request do
  @moduledoc false
  # build script lives outside lib/ so it is not part of the runtime app
  @external_resource Path.expand("../build/curl_impersonate.ex", __DIR__)
  Code.require_file("../build/curl_impersonate.ex", __DIR__)

  use Zig,
    otp_app: :ex_curl_impersonate,
    c: ExCurlImpersonate.Build.zig_c_opts(),
    nifs: [request: [:dirty_io], curl_version: []]
```

Add to the `~Z` block (after `pub const Response ...`):

```zig
pub fn curl_version() []const u8 {
    return std.mem.sliceTo(cURL.curl_version(), 0);
}
```

`lib/ex_curl_impersonate.ex`, after `request!/3`:

```elixir
  @doc """
  Returns the version string of the linked libcurl, e.g. `"libcurl/8.22.0-IMPERSONATE BoringSSL/..."`.
  """
  def curl_version, do: Request.curl_version()
```

- [ ] **Step 5: Run the full suite**

Run: `mise exec -- mix test`
Expected: PASS, including `build_test.exs` and "is linked against libcurl-impersonate". First compile prints `Downloading libcurl-impersonate-v2.2.3.x86_64-linux-gnu.tar.gz`.

Then verify linkage:

Run: `readelf -d _build/test/lib/ex_curl_impersonate/priv/lib/Elixir.ExCurlImpersonate.Request.so | grep -E 'NEEDED|RUNPATH'; ls _build/test/lib/ex_curl_impersonate/priv/lib/`
Expected: `NEEDED [libcurl-impersonate.so.4]`, no `libcurl.so.4`, `RUNPATH [$ORIGIN]`; dir lists `libcurl-impersonate.so.4`.

- [ ] **Step 6: Verify as a dependency and in a release (Review Focus 5)**

In a scratch directory outside the repo (e.g. the session scratchpad):

```bash
SCRATCH=$(mktemp -d)
cd "$SCRATCH" && rm -rf depcheck && mise exec -- mix new depcheck && cd depcheck
cp /home/john/Projects/elixir/ex_curl/mise.toml .
sed -i 's|# {:dep_from_hexpm.*|{:ex_curl_impersonate, path: "/home/john/Projects/elixir/ex_curl"},|' mix.exs
mise exec -- mix deps.get
mise exec -- mix run -e 'IO.puts ExCurlImpersonate.curl_version()'
MIX_ENV=prod mise exec -- mix release --overwrite
_build/prod/rel/depcheck/bin/depcheck eval 'IO.puts ExCurlImpersonate.curl_version()'
```

Expected: both print a version containing `IMPERSONATE`; `ls _build/prod/rel/depcheck/lib/ex_curl_impersonate-0.1.0/priv/lib/` lists the NIF and `libcurl-impersonate.so.4`.

- [ ] **Step 7: Test the env-var escape hatch**

```bash
CURL_IMPERSONATE_DIR=$(ls -d _build/test/curl_impersonate/2.2.3/*) mise exec -- mix compile --force && mise exec -- mix test test/ex_curl_impersonate_test.exs
```

Expected: no download line, tests PASS.

- [ ] **Step 8: Toolchain / CI**

- `devenv.nix`: remove the `pkgs.curl` line.
- `.github/workflows/ci.yml`:
  - ubuntu: change the install step to nothing curl-related — delete the `Install test dependencies` and `Setup Kerberos environment...` steps; replace `--include kerberos:true` with nothing in both `mix test` lines (`mix test` and `mix test --warnings-as-errors`).
  - both jobs: add before `mix test`:
    ```yaml
      - uses: actions/cache@v4
        with:
          path: _build/test/curl_impersonate
          key: curl-impersonate-2.2.3-${{ runner.os }}-${{ runner.arch }}
    ```
- `.github/workflows/publish.yml`: delete the `Install build dependencies` step.

- [ ] **Step 9: Commit**

```bash
mise exec -- mix format
git add -A && git commit -m "feat: link against prebuilt libcurl-impersonate

Downloads the pinned curl-impersonate release at compile time, verifies
its sha256 and ships the shared library next to the NIF in priv/lib.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `:impersonate`, `:http_version` and `Response.http_version`

**Files:**
- Modify: `lib/request_configuration.ex`, `lib/request.ex`, `lib/response.ex`, `lib/ex_curl_impersonate.ex` (docs)
- Create: `test/request_configuration_test.exs`, `test/impersonate_test.exs`

**Interfaces:**
- Consumes: Task 2 NIF.
- Produces:
  - `RequestConfiguration.build/3` flags gain `impersonate: nil | binary`, `impersonate_default_headers: boolean`, `http_version: nil | integer`.
  - Zig `RequestFlags` same fields (`?[]u8`, `bool`, `?i64`); Zig `Response.http_version: i64`.
  - `%ExCurlImpersonate.Response{http_version: nil | :http1_0 | :http1_1 | :http2 | :http3}`.
  - Zig `setCurlOpts(...) !cURL.CURLcode` — returns non-OK code instead of `unreachable` for impersonate/new opts.

- [ ] **Step 1: Write failing unit tests**

`test/request_configuration_test.exs`:

```elixir
defmodule ExCurlImpersonate.RequestConfigurationTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.RequestConfiguration

  defp header_keys(config), do: Enum.map(config.headers, &String.downcase(&1.key))

  test "impersonate defaults" do
    config = RequestConfiguration.build("GET", "http://x")
    assert config.flags.impersonate == nil
    assert config.flags.impersonate_default_headers == true
    assert config.flags.http_version == nil
  end

  test "adds the library user-agent only when not impersonating" do
    assert "user-agent" in header_keys(RequestConfiguration.build("GET", "http://x"))
    refute "user-agent" in header_keys(RequestConfiguration.build("GET", "http://x", impersonate: "chrome136"))
  end

  test "keeps a user-supplied user-agent when impersonating" do
    config = RequestConfiguration.build("GET", "http://x", impersonate: "chrome136", headers: %{"User-Agent" => "mine"})
    assert [%{key: "User-Agent", value: "mine"}] = config.headers
  end

  test "maps http_version atoms to CURL_HTTP_VERSION values" do
    for {atom, value} <- [http1_0: 1, http1_1: 2, http2: 3, http2_tls: 4, http2_prior_knowledge: 5, http3: 30, http3_only: 31] do
      assert RequestConfiguration.build("GET", "http://x", http_version: atom).flags.http_version == value
    end
  end

  test "rejects invalid http_version and impersonate values" do
    assert_raise ArgumentError, ~r/:http_version/, fn ->
      RequestConfiguration.build("GET", "http://x", http_version: :http4)
    end

    assert_raise ArgumentError, ~r/:impersonate/, fn ->
      RequestConfiguration.build("GET", "http://x", impersonate: :chrome)
    end
  end
end
```

`test/impersonate_test.exs`:

```elixir
defmodule ExCurlImpersonate.ImpersonateTest do
  use ExUnit.Case, async: true

  alias ExCurlImpersonate.TestClient

  setup do
    {:ok, bypass: Bypass.open()}
  end

  defp echo_headers(bypass) do
    Bypass.expect(bypass, "GET", "/h", fn conn ->
      Plug.Conn.send_resp(conn, 200, Jason.encode!(Map.new(conn.req_headers)))
    end)
  end

  defp get_headers(bypass, opts) do
    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/h", opts)
    Jason.decode!(resp.body)
  end

  test "impersonate sends the browser's default headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136")
    assert headers["sec-ch-ua"] =~ "Chrome"
    assert "Mozilla/5.0" <> _ = headers["user-agent"]
  end

  test "impersonate_default_headers: false omits them", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", impersonate_default_headers: false)
    refute Map.has_key?(headers, "sec-ch-ua")
    refute String.starts_with?(headers["user-agent"] || "", "ex_curl_impersonate/")
  end

  test "a user-supplied user-agent overrides the preset", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", headers: %{"user-agent" => "mine"})
    assert headers["user-agent"] == "mine"
  end

  test "unknown impersonate target returns an error" do
    assert {:error, "BAD_FUNCTION_ARGUMENT"} =
             ExCurlImpersonate.get("http://localhost:1/", impersonate: "netscape4")
  end

  test "reports the negotiated http version", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/v", &Plug.Conn.send_resp(&1, 200, "OK"))
    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/v")
    assert resp.http_version == :http1_1
  end

  test "http_version: :http1_0 is honoured", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/v", &Plug.Conn.send_resp(&1, 200, "OK"))
    {:ok, resp} = TestClient.get("http://localhost:#{bypass.port}/v", http_version: :http1_0)
    assert resp.http_version == :http1_0
  end
end
```

Note: with `impersonate:` over plain `http://`, curl also sends an h2c upgrade (verified), so impersonate tests don't assert `http_version`.

- [ ] **Step 2: Run to verify failure**

Run: `mise exec -- mix test test/request_configuration_test.exs test/impersonate_test.exs`
Expected: FAIL (`KeyError :impersonate`, missing `http_version` field, etc.).

- [ ] **Step 3: Elixir side**

`lib/request_configuration.ex` — replace `build/3` and `get_headers/1`:

```elixir
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
```

`lib/response.ex` — add field, type, parse:

```elixir
  defstruct body: "",
            headers: %{},
            status_code: 200,
            http_version: nil,
            metrics: nil
```

type: `http_version: nil | :http1_0 | :http1_1 | :http2 | :http3,`

in `parse/1`: add `http_version: parse_http_version(response.http_version),` and:

```elixir
  # CURLINFO_HTTP_VERSION values
  defp parse_http_version(1), do: :http1_0
  defp parse_http_version(2), do: :http1_1
  defp parse_http_version(3), do: :http2
  defp parse_http_version(30), do: :http3
  defp parse_http_version(_), do: nil
```

- [ ] **Step 4: Zig side**

In `lib/request.ex`:

`RequestFlags` becomes:

```zig
pub const RequestFlags = struct {
    follow_location: bool,
    ssl_verifyhost: bool,
    ssl_verifypeer: bool,
    return_metrics: bool,
    verbose: bool,
    proxy: ?[]u8,
    impersonate: ?[]u8,
    impersonate_default_headers: bool,
    http_version: ?i64,
};
```

`Response` gains `http_version: i64,`.

In `request()`, replace `try setCurlOpts(allocator, handle, config);` with:

```zig
    const opts_result = try setCurlOpts(allocator, handle, config);
    if (opts_result != cURL.CURLE_OK)
        return beam.make_error_pair(opts_result, .{});
```

`setCurlOpts` signature → `fn setCurlOpts(allocator: std.mem.Allocator, handle: *cURL.CURL, config: RequestConfiguration) !cURL.CURLcode`, with this at the very top of its body (before the bool flags, so later options override the preset):

```zig
    if (config.flags.impersonate) |target| {
        const c_target = try allocator.dupeZ(u8, target);
        defer allocator.free(c_target);
        const default_headers: c_int = if (config.flags.impersonate_default_headers) 1 else 0;
        const rc = cURL.curl_easy_impersonate(handle, c_target.ptr, default_headers);
        if (rc != cURL.CURLE_OK) return rc;
    }
```

after the proxy block, before the end:

```zig
    if (config.flags.http_version) |version| {
        const rc = cURL.curl_easy_setopt(handle, cURL.CURLOPT_HTTP_VERSION, @as(c_long, @intCast(version)));
        if (rc != cURL.CURLE_OK) return rc;
    }

    return cURL.CURLE_OK;
```

In `makeResponse`, before `return .{`:

```zig
    var http_version: c_long = 0;
    if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_HTTP_VERSION, &http_version) != cURL.CURLE_OK)
        return error.CURLGETINFO_FAILED;
```

and add `.http_version = http_version,` to the returned struct.

- [ ] **Step 5: Docs**

In `lib/ex_curl_impersonate.ex` "Shared options", after `:proxy`:

```markdown
    * `:impersonate` - browser to impersonate (TLS, HTTP/2 fingerprint and default headers), e.g. `"chrome136"`, `"safari18_0"`, `"firefox135"`. See the [curl-impersonate targets](https://github.com/lexiforest/curl-impersonate#supported-browsers). When set, the default `user-agent` header is not added. Defaults to `nil`
    * `:impersonate_default_headers` - whether `:impersonate` also sends the browser's default headers. Defaults to `true`
    * `:http_version` - one of `:http1_0`, `:http1_1`, `:http2`, `:http2_tls`, `:http2_prior_knowledge`, `:http3` (falls back if HTTP/3 fails) or `:http3_only`. Defaults to `nil` (curl's default, or the impersonated browser's)
```

and the default-header bullet: `defaults to %{"user-agent" => "ex_curl_impersonate/0.1.0"} (not added when :impersonate is set)`.

In `lib/response.ex` moduledoc add: `` `http_version` - the HTTP version used for the response (`:http1_0`, `:http1_1`, `:http2`, `:http3`). ``

- [ ] **Step 6: Run tests**

Run: `mise exec -- mix test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
mise exec -- mix format
git add -A && git commit -m "feat: add impersonate and http_version options

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: curl-impersonate fingerprint options

**Files:**
- Modify: `lib/request_configuration.ex`, `lib/request.ex`, `lib/ex_curl_impersonate.ex` (docs)
- Modify: `test/request_configuration_test.exs`, `test/impersonate_test.exs`

**Interfaces:**
- Consumes: Task 3 `setCurlOpts(...) !cURL.CURLcode`, `RequestConfiguration.build/3`.
- Produces:
  - `RequestConfiguration` struct fields `long_opts`, `string_opts`, `slist_opts` (maps keyed by option atom, values `nil | integer`, `nil | binary`, `nil | [binary]`).
  - `RequestConfiguration.long_opts/0`, `string_opts/0`, `slist_opts/0` return the option atom lists (used by docs/tests).

- [ ] **Step 1: Write failing tests**

Append to `test/request_configuration_test.exs`:

```elixir
  describe "fingerprint options" do
    test "default to nil" do
      config = RequestConfiguration.build("GET", "http://x")
      assert Enum.all?(Map.values(config.long_opts), &is_nil/1)
      assert Enum.all?(Map.values(config.string_opts), &is_nil/1)
      assert Enum.all?(Map.values(config.slist_opts), &is_nil/1)
      assert map_size(config.long_opts) == 18
      assert map_size(config.string_opts) == 20
      assert map_size(config.slist_opts) == 3
    end

    test "booleans become 1/0 and false is not dropped" do
      config = RequestConfiguration.build("GET", "http://x", tls_grease: true, ssl_enable_ticket: false, tls_record_size_limit: 4001)
      assert config.long_opts.tls_grease == 1
      assert config.long_opts.ssl_enable_ticket == 0
      assert config.long_opts.tls_record_size_limit == 4001
    end

    test "strings and lists pass through" do
      config = RequestConfiguration.build("GET", "http://x", http2_settings: "1:65536", httpbaseheader: ["a: 1"])
      assert config.string_opts.http2_settings == "1:65536"
      assert config.slist_opts.httpbaseheader == ["a: 1"]
    end

    test "wrong types raise ArgumentError naming the option" do
      assert_raise ArgumentError, ~r/:tls_grease/, fn ->
        RequestConfiguration.build("GET", "http://x", tls_grease: "yes")
      end

      assert_raise ArgumentError, ~r/:http2_settings/, fn ->
        RequestConfiguration.build("GET", "http://x", http2_settings: 1)
      end

      assert_raise ArgumentError, ~r/:httpbaseheader/, fn ->
        RequestConfiguration.build("GET", "http://x", httpbaseheader: "a: 1")
      end
    end
  end
```

Append to `test/impersonate_test.exs`:

```elixir
  test "httpbaseheader replaces the preset base headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", httpbaseheader: ["x-base: 1"])
    assert headers["x-base"] == "1"
    refute Map.has_key?(headers, "sec-ch-ua")
  end

  test "httpbaseheader: [] clears the preset base headers", %{bypass: bypass} do
    echo_headers(bypass)
    headers = get_headers(bypass, impersonate: "chrome136", httpbaseheader: [])
    refute Map.has_key?(headers, "sec-ch-ua")
  end

  test "long and string options are accepted by curl", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/v", &Plug.Conn.send_resp(&1, 200, "OK"))

    assert {:ok, %{status_code: 200}} =
             TestClient.get("http://localhost:#{bypass.port}/v",
               tls_grease: true,
               ssl_enable_ticket: false,
               http2_settings: "1:65536;4:6291456",
               tls_extension_order: "0-23-65281-10-11-35-16-5-13-18-51-45-43-27-17513"
             )
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mise exec -- mix test test/request_configuration_test.exs test/impersonate_test.exs`
Expected: FAIL (`KeyError :long_opts`; httpbaseheader tests see `sec-ch-ua`).

- [ ] **Step 3: Elixir side**

`lib/request_configuration.ex`:

```elixir
  defstruct headers: %{},
            url: "",
            method: "",
            body: "",
            flags: %{},
            long_opts: %{},
            string_opts: %{},
            slist_opts: %{}

  # curl-impersonate CURLOPT_* additions; names must match the Zig tables in ExCurlImpersonate.Request
  @long_opts ~w(http2_no_priority http2_window_update http3_ssl_permute_extensions
                proxy_credential_no_reuse quic_initial_packet_number split_cookies
                ssl_enable_alps ssl_enable_ticket ssl_permute_extensions stream_exclusive
                tls_grease tls_key_shares_limit tls_key_usage_no_check tls_record_size_limit
                tls_signed_cert_timestamps tls_status_request tls_use_new_alps_codepoint
                ws_ssl_disable_ticket)a
  @string_opts ~w(form_boundary http2_pseudo_headers_order http2_settings http2_streams
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
```

In `build/3` struct literal add:

```elixir
      long_opts: Map.new(@long_opts, &{&1, long_value(&1, opts[&1])}),
      string_opts: Map.new(@string_opts, &{&1, string_value(&1, opts[&1])}),
      slist_opts: Map.new(@slist_opts, &{&1, slist_value(&1, opts[&1])})
```

and:

```elixir
  defp long_value(_, nil), do: nil
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
```

- [ ] **Step 4: Zig side**

In `lib/request.ex` add structs (after `RequestFlags`):

```zig
pub const LongOpts = struct {
    http2_no_priority: ?i64,
    http2_window_update: ?i64,
    http3_ssl_permute_extensions: ?i64,
    proxy_credential_no_reuse: ?i64,
    quic_initial_packet_number: ?i64,
    split_cookies: ?i64,
    ssl_enable_alps: ?i64,
    ssl_enable_ticket: ?i64,
    ssl_permute_extensions: ?i64,
    stream_exclusive: ?i64,
    tls_grease: ?i64,
    tls_key_shares_limit: ?i64,
    tls_key_usage_no_check: ?i64,
    tls_record_size_limit: ?i64,
    tls_signed_cert_timestamps: ?i64,
    tls_status_request: ?i64,
    tls_use_new_alps_codepoint: ?i64,
    ws_ssl_disable_ticket: ?i64,
};

pub const StringOpts = struct {
    form_boundary: ?[]u8,
    http2_pseudo_headers_order: ?[]u8,
    http2_settings: ?[]u8,
    http2_streams: ?[]u8,
    http3_httpheader_order: ?[]u8,
    http3_pseudo_headers_order: ?[]u8,
    http3_settings: ?[]u8,
    http3_sig_hash_algs: ?[]u8,
    http3_ssl_ec_curves: ?[]u8,
    http3_tls_extension_order: ?[]u8,
    httpheader_order: ?[]u8,
    quic_cid_length: ?[]u8,
    quic_transport_parameters: ?[]u8,
    ssl_cert_compression: ?[]u8,
    ssl_sig_hash_algs: ?[]u8,
    tls_delegated_credentials: ?[]u8,
    tls_extension_order: ?[]u8,
    tls_trust_anchors: ?[]u8,
    ws_httpheader_order: ?[]u8,
    ws_ssl_cert_compression: ?[]u8,
};

pub const SlistOpts = struct {
    httpbaseheader: ?[][]u8,
    http3_httpheader: ?[][]u8,
    ws_httpheader: ?[][]u8,
};
```

`RequestConfiguration` gains `long_opts: LongOpts, string_opts: StringOpts, slist_opts: SlistOpts,`.

Tables (next to `bool_flag_opts`):

```zig
const long_opts = .{
    .{ "http2_no_priority", cURL.CURLOPT_HTTP2_NO_PRIORITY },
    .{ "http2_window_update", cURL.CURLOPT_HTTP2_WINDOW_UPDATE },
    .{ "http3_ssl_permute_extensions", cURL.CURLOPT_HTTP3_SSL_PERMUTE_EXTENSIONS },
    .{ "proxy_credential_no_reuse", cURL.CURLOPT_PROXY_CREDENTIAL_NO_REUSE },
    .{ "quic_initial_packet_number", cURL.CURLOPT_QUIC_INITIAL_PACKET_NUMBER },
    .{ "split_cookies", cURL.CURLOPT_SPLIT_COOKIES },
    .{ "ssl_enable_alps", cURL.CURLOPT_SSL_ENABLE_ALPS },
    .{ "ssl_enable_ticket", cURL.CURLOPT_SSL_ENABLE_TICKET },
    .{ "ssl_permute_extensions", cURL.CURLOPT_SSL_PERMUTE_EXTENSIONS },
    .{ "stream_exclusive", cURL.CURLOPT_STREAM_EXCLUSIVE },
    .{ "tls_grease", cURL.CURLOPT_TLS_GREASE },
    .{ "tls_key_shares_limit", cURL.CURLOPT_TLS_KEY_SHARES_LIMIT },
    .{ "tls_key_usage_no_check", cURL.CURLOPT_TLS_KEY_USAGE_NO_CHECK },
    .{ "tls_record_size_limit", cURL.CURLOPT_TLS_RECORD_SIZE_LIMIT },
    .{ "tls_signed_cert_timestamps", cURL.CURLOPT_TLS_SIGNED_CERT_TIMESTAMPS },
    .{ "tls_status_request", cURL.CURLOPT_TLS_STATUS_REQUEST },
    .{ "tls_use_new_alps_codepoint", cURL.CURLOPT_TLS_USE_NEW_ALPS_CODEPOINT },
    .{ "ws_ssl_disable_ticket", cURL.CURLOPT_WS_SSL_DISABLE_TICKET },
};

const string_opts = .{
    .{ "form_boundary", cURL.CURLOPT_FORM_BOUNDARY },
    .{ "http2_pseudo_headers_order", cURL.CURLOPT_HTTP2_PSEUDO_HEADERS_ORDER },
    .{ "http2_settings", cURL.CURLOPT_HTTP2_SETTINGS },
    .{ "http2_streams", cURL.CURLOPT_HTTP2_STREAMS },
    .{ "http3_httpheader_order", cURL.CURLOPT_HTTP3_HTTPHEADER_ORDER },
    .{ "http3_pseudo_headers_order", cURL.CURLOPT_HTTP3_PSEUDO_HEADERS_ORDER },
    .{ "http3_settings", cURL.CURLOPT_HTTP3_SETTINGS },
    .{ "http3_sig_hash_algs", cURL.CURLOPT_HTTP3_SIG_HASH_ALGS },
    .{ "http3_ssl_ec_curves", cURL.CURLOPT_HTTP3_SSL_EC_CURVES },
    .{ "http3_tls_extension_order", cURL.CURLOPT_HTTP3_TLS_EXTENSION_ORDER },
    .{ "httpheader_order", cURL.CURLOPT_HTTPHEADER_ORDER },
    .{ "quic_cid_length", cURL.CURLOPT_QUIC_CID_LENGTH },
    .{ "quic_transport_parameters", cURL.CURLOPT_QUIC_TRANSPORT_PARAMETERS },
    .{ "ssl_cert_compression", cURL.CURLOPT_SSL_CERT_COMPRESSION },
    .{ "ssl_sig_hash_algs", cURL.CURLOPT_SSL_SIG_HASH_ALGS },
    .{ "tls_delegated_credentials", cURL.CURLOPT_TLS_DELEGATED_CREDENTIALS },
    .{ "tls_extension_order", cURL.CURLOPT_TLS_EXTENSION_ORDER },
    .{ "tls_trust_anchors", cURL.CURLOPT_TLS_TRUST_ANCHORS },
    .{ "ws_httpheader_order", cURL.CURLOPT_WS_HTTPHEADER_ORDER },
    .{ "ws_ssl_cert_compression", cURL.CURLOPT_WS_SSL_CERT_COMPRESSION },
};

const slist_opts = .{
    .{ "httpbaseheader", cURL.CURLOPT_HTTPBASEHEADER },
    .{ "http3_httpheader", cURL.CURLOPT_HTTP3_HTTPHEADER },
    .{ "ws_httpheader", cURL.CURLOPT_WS_HTTPHEADER },
};
```

The slists must outlive `curl_easy_perform`, so `request()` owns them. In `request()`, right after `defer cURL.curl_easy_cleanup(handle);`:

```zig
    var slists = [_][*c]cURL.curl_slist{null} ** slist_opts.len;
    defer for (slists) |list| cURL.curl_slist_free_all(list);
```

and the call becomes `const opts_result = try setCurlOpts(allocator, handle, config, &slists);`.

`setCurlOpts` signature: `fn setCurlOpts(allocator: std.mem.Allocator, handle: *cURL.CURL, config: RequestConfiguration, slists: *[slist_opts.len][*c]cURL.curl_slist) !cURL.CURLcode`. Before its final `return cURL.CURLE_OK;`:

```zig
    inline for (long_opts) |opt| {
        if (@field(config.long_opts, opt[0])) |value| {
            const rc = cURL.curl_easy_setopt(handle, opt[1], @as(c_long, @intCast(value)));
            if (rc != cURL.CURLE_OK) return rc;
        }
    }

    inline for (string_opts) |opt| {
        if (@field(config.string_opts, opt[0])) |value| {
            const c_string = try allocator.dupeZ(u8, value);
            defer allocator.free(c_string);
            const rc = cURL.curl_easy_setopt(handle, opt[1], c_string.ptr);
            if (rc != cURL.CURLE_OK) return rc;
        }
    }

    inline for (0..slist_opts.len) |i| {
        const opt = slist_opts[i];
        if (@field(config.slist_opts, opt[0])) |items| {
            for (items) |item| {
                const c_item = try allocator.dupeZ(u8, item);
                defer allocator.free(c_item);
                slists[i] = cURL.curl_slist_append(slists[i], c_item.ptr);
            }
            // an empty list sets NULL, clearing e.g. the impersonate base headers
            const rc = cURL.curl_easy_setopt(handle, opt[1], slists[i]);
            if (rc != cURL.CURLE_OK) return rc;
        }
    }
```

(curl copies string options and `curl_slist_append` copies items, so freeing the dup'd buffers is safe.)

- [ ] **Step 5: Docs**

In `lib/ex_curl_impersonate.ex` moduledoc, after "Shared options", add:

```markdown
  ## Fingerprint options

  Every option added by [curl-impersonate](https://github.com/lexiforest/curl-impersonate) is available, named after the
  lowercased `CURLOPT_` constant (e.g. `CURLOPT_TLS_GREASE` → `:tls_grease`). They default to `nil` (not set) and are applied
  after `:impersonate`, so they override the preset.

    * integer / boolean: `:http2_no_priority`, `:http2_window_update`, `:http3_ssl_permute_extensions`, `:proxy_credential_no_reuse`,
      `:quic_initial_packet_number`, `:split_cookies`, `:ssl_enable_alps`, `:ssl_enable_ticket`, `:ssl_permute_extensions`,
      `:stream_exclusive`, `:tls_grease`, `:tls_key_shares_limit`, `:tls_key_usage_no_check`, `:tls_record_size_limit`,
      `:tls_signed_cert_timestamps`, `:tls_status_request`, `:tls_use_new_alps_codepoint`, `:ws_ssl_disable_ticket`
    * string: `:form_boundary`, `:http2_pseudo_headers_order`, `:http2_settings`, `:http2_streams`, `:http3_httpheader_order`,
      `:http3_pseudo_headers_order`, `:http3_settings`, `:http3_sig_hash_algs`, `:http3_ssl_ec_curves`, `:http3_tls_extension_order`,
      `:httpheader_order`, `:quic_cid_length`, `:quic_transport_parameters`, `:ssl_cert_compression`, `:ssl_sig_hash_algs`,
      `:tls_delegated_credentials`, `:tls_extension_order`, `:tls_trust_anchors`, `:ws_httpheader_order`, `:ws_ssl_cert_compression`
    * list of `"Name: value"` strings: `:httpbaseheader`, `:http3_httpheader`, `:ws_httpheader`.
      `httpbaseheader: []` removes the impersonated browser's default headers.
```

- [ ] **Step 6: Run tests**

Run: `mise exec -- mix test && mise exec -- mix compile --force --warnings-as-errors`
Expected: PASS, no warnings.

- [ ] **Step 7: Commit**

```bash
mise exec -- mix format
git add -A && git commit -m "feat: expose curl-impersonate fingerprint options

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: External fingerprint / HTTP/3 tests and README

**Files:**
- Create: `test/external_test.exs`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the external tests**

`test/external_test.exs`:

```elixir
defmodule ExCurlImpersonate.ExternalTest do
  use ExUnit.Case, async: true

  # Hits the network; run with: mix test --only external
  @moduletag :external

  defp fingerprint(opts) do
    {:ok, resp} = ExCurlImpersonate.get("https://tls.peet.ws/api/all", opts)
    Jason.decode!(resp.body)
  end

  test "impersonating chrome changes the TLS and HTTP/2 fingerprint" do
    chrome = fingerprint(impersonate: "chrome136")
    plain = fingerprint([])

    assert chrome["user_agent"] =~ "Chrome/136"
    assert chrome["http_version"] == "h2"
    refute chrome["tls"]["ja4"] == plain["tls"]["ja4"]
    refute chrome["http2"]["akamai_fingerprint_hash"] == plain["http2"]["akamai_fingerprint_hash"]
    # Chrome sends GREASE values; stock curl does not
    assert Enum.any?(chrome["tls"]["extensions"], &String.contains?(&1["name"], "GREASE"))
  end

  test "http3_only negotiates HTTP/3" do
    assert {:ok, %{http_version: :http3}} =
             ExCurlImpersonate.get("https://cloudflare-quic.com/",
               impersonate: "chrome136",
               http_version: :http3_only
             )
  end
end
```

- [ ] **Step 2: Run them**

Run: `mise exec -- mix test --only external`
Expected: PASS. If a field name in tls.peet.ws's JSON differs, inspect `fingerprint(impersonate: "chrome136")` in `iex -S mix` and adjust the key path — the assertions' intent (Chrome UA, h2, ja4 and akamai hash differ from plain, GREASE present) must stay.

- [ ] **Step 3: README**

Replace the intro/usage section of `README.md` with:

````markdown
# ExCurlImpersonate

Elixir bindings for [curl-impersonate](https://github.com/lexiforest/curl-impersonate) using Zig's C interoperability:
make HTTP requests with the TLS (JA3/JA4) and HTTP/2/HTTP/3 fingerprints of real browsers.

Fork of [ex_curl](https://github.com/danielrudn/ex_curl) by Daniel Rudnitski.

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

Supported platforms: Linux x86_64/aarch64 (glibc and musl), macOS arm64/x86_64.
For other platforms or offline builds, set `CURL_IMPERSONATE_DIR` to a directory containing `include/curl/curl.h` and
`libcurl-impersonate.so` (or `.dylib`).

## Usage

```elixir
ExCurlImpersonate.get("https://tls.peet.ws/api/all", impersonate: "chrome136")

# HTTP/3
ExCurlImpersonate.get("https://cloudflare-quic.com/", impersonate: "chrome136", http_version: :http3_only)

# fine-tune the fingerprint
ExCurlImpersonate.get("https://example.com", impersonate: "chrome136", tls_grease: false, httpbaseheader: [])
```

See the `ExCurlImpersonate` module docs for all options.

## Licensing

This package is MIT licensed. The downloaded `libcurl-impersonate` bundles curl, BoringSSL, nghttp2, nghttp3, ngtcp2,
brotli, zstd, zlib and libidn2 (LGPL-3.0/GPL-2.0); their licenses are in the release tarball, extracted to
`_build/<env>/curl_impersonate/`.
````

Keep the existing "HTTP Clients and Shared Defaults" section (already renamed in Task 1) below Usage.

- [ ] **Step 4: Final verification**

Run:
```bash
mise exec -- mix format --check-formatted
mise exec -- mix deps.unlock --check-unused
mise exec -- mix compile --force --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --only external
mise exec -- mix docs
```
Expected: all pass; docs build without warnings.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "test: add external fingerprint and HTTP/3 tests; docs: README for ex_curl_impersonate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
