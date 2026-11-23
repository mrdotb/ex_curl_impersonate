defmodule ExCurlImpersonate.Build do
  @moduledoc false
  # Compile-time helper: fetches the pinned libcurl-impersonate release for the
  # host, installs the shared library next to the NIF and returns the Zigler
  # `c:` options. Loaded via Code.require_file from lib/request.ex.

  @upstream "https://github.com/lexiforest/curl-impersonate/releases/download"
  # x86_64-linux-gnu comes from our fork, which adds the chrome153-157 targets
  @fork "https://github.com/mrdotb/curl-impersonate/releases/download"
  @releases %{
    "x86_64-linux-gnu" =>
      {@fork, "2.3.2-chrome157", "7f093a47c0d1c40013b1a9b6a5e047dcf0f53f714a1041b43ee2ce52c9696001"},
    "aarch64-linux-gnu" =>
      {@upstream, "2.3.2", "1cb74a3b5103df020c252f9efef5a779c87380ee6244b365a90a0e4f7086864e"},
    "x86_64-linux-musl" =>
      {@upstream, "2.3.2", "117ace4923c168d38bc87e7e4c4f55ebe2b14c1714829c76b95a77a8f0b9c059"},
    "aarch64-linux-musl" =>
      {@upstream, "2.3.2", "9cb9959f25271ee457a16fb3f5e2bd0c3fccd0a45cf0d4b97ed2d59f310737d6"},
    "arm64-macos" =>
      {@upstream, "2.3.2", "6c0dc841a8f6b7a8f81a0f55197e8241405fb7dcd97df180e66fc6f796c42bd5"},
    "x86_64-macos" =>
      {@upstream, "2.3.2", "eed3342d8768065ab7a9106f4286d9101959b7e9e1b2b969eb8d8be1a52422cd"}
  }

  def version(triple), do: elem(Map.fetch!(@releases, triple), 1)
  def checksum(triple), do: elem(Map.fetch!(@releases, triple), 2)

  def zig_c_opts do
    os = host_os()
    %{link_name: link_name, soname: soname, rpath: rpath} = layout(os)
    dir = lib_dir!()
    install!(Path.join(dir, link_name), soname)

    [
      include_dirs: Path.join(dir, "include"),
      link_lib: Path.join(dir, link_name),
      # the NIF loads the copy next to it in priv/lib; the absolute dir lets
      # Zigler's sema executable (run during compilation) find the library too
      rpaths: [{:special, rpath}, dir]
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

    {base_url, version, _} = Map.fetch!(@releases, triple)
    dir = Path.join([Mix.Project.build_path(), "curl_impersonate", version, triple])

    unless File.exists?(Path.join(dir, "include/curl/curl.h")) do
      asset = "libcurl-impersonate-v#{version}.#{triple}.tar.gz"
      Mix.shell().info("Downloading #{asset}")
      data = download!("#{base_url}/v#{version}/#{asset}")
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

    # GitHub's headers (mostly content-security-policy) exceed httpc's 10240 byte default
    opts = [body_format: :binary, max_header_size: 65_536]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl], opts) do
      {:ok, {{_, 200, _}, _headers, body}} -> body
      other -> Mix.raise("Failed to download #{url}: #{inspect(other)}")
    end
  end

  # Copy (following symlinks) into the dir Zigler writes the NIF to, under the
  # soname the NIF records as NEEDED, so the rpath finds it at load time.
  # The target may already be mapped by a running VM, so never rewrite it in
  # place: skip if identical, else copy to a temp file and rename over it.
  defp install!(lib_path, soname) do
    File.exists?(lib_path) || Mix.raise("libcurl-impersonate not found at #{lib_path}")
    priv_lib = Path.join(Mix.Project.app_path(), "priv/lib")
    File.mkdir_p!(priv_lib)
    target = Path.join(priv_lib, soname)

    unless same_file?(lib_path, target) do
      tmp = target <> ".tmp"
      File.cp!(lib_path, tmp)
      File.rename!(tmp, target)
    end

    install_licenses!(Path.dirname(lib_path), priv_lib)
  end

  defp same_file?(a, b) do
    with {:ok, %{size: size}} <- File.stat(a),
         {:ok, %{size: ^size}} <- File.stat(b) do
      hash(a) == hash(b)
    else
      _ -> false
    end
  end

  defp hash(path), do: :crypto.hash(:sha256, File.read!(path))

  defp install_licenses!(dir, priv_lib) do
    case Path.wildcard(Path.join(dir, "LICENSE*")) do
      [] ->
        :ok

      files ->
        dest = Path.join(priv_lib, "curl-impersonate-licenses")
        File.mkdir_p!(dest)
        Enum.each(files, &File.cp!(&1, Path.join(dest, Path.basename(&1))))
    end
  end
end
