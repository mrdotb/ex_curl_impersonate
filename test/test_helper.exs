# The build script is not in lib/; it is normally already loaded (and compiled
# into ebin) by lib/request.ex, so only load it when missing.
Code.ensure_loaded?(ExCurlImpersonate.Build) ||
  Code.require_file("../build/curl_impersonate.ex", __DIR__)

ExUnit.configure(exclude: [external: true])
ExUnit.start()
