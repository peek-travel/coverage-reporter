defmodule CoverageReporter.MixProject do
  use Mix.Project

  @app :coverage_reporter

  def project do
    [
      app: @app,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      test_coverage: [tool: LcovEx],
      escript: [main_module: CoverageReporter]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:briefly, "~> 0.4.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.2"},
      {:lcov_ex, "~> 0.3", only: [:dev, :test], runtime: false},
      {:req, "~> 0.4.4"}
    ]
  end
end
