defmodule ExCurlImpersonate.MixProject do
  use Mix.Project

  @source_url "https://github.com/mrdotb/ex_curl_impersonate"

  def project do
    [
      app: :ex_curl_impersonate,
      version: "0.2.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.39", runtime: false},
      {:bypass, "~> 2.0", only: :test},
      {:zigler, "~> 0.16", runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp package do
    [
      description:
        "Elixir bindings for libcurl-impersonate (browser TLS/HTTP2 fingerprint impersonation).",
      maintainers: ["mrdotb"],
      licenses: ["MIT"],
      files: ~w(lib build mix.exs README.md LICENSE .formatter.exs),
      exclude_patterns: [~r/\.Elixir\..*\.zig$/],
      links: %{"GitHub" => @source_url}
    ]
  end
end
