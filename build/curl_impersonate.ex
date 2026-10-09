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
