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
      assert Build.verify_checksum!(
               "abc",
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
             ) == :ok
    end

    test "raises on mismatch" do
      assert_raise Mix.Error, ~r/checksum mismatch/, fn ->
        Build.verify_checksum!("abc", String.duplicate("0", 64))
      end
    end
  end

  test "layout/1 names the shared library per OS" do
    assert Build.layout(:linux) ==
             %{
               link_name: "libcurl-impersonate.so",
               soname: "libcurl-impersonate.so.4",
               rpath: "$ORIGIN"
             }

    assert Build.layout(:macos) ==
             %{
               link_name: "libcurl-impersonate.dylib",
               soname: "libcurl-impersonate.4.dylib",
               rpath: "@loader_path"
             }
  end

  test "has a checksum for every supported triple" do
    for t <-
          ~w(x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl aarch64-linux-musl arm64-macos x86_64-macos) do
      assert Build.checksum(t) =~ ~r/^[0-9a-f]{64}$/
    end
  end
end
