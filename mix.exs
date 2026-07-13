defmodule DemoExWapp.MixProject do
  use Mix.Project

  def project do
    [
      app: :demo_ex_wapp,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      mod: {DemoExWapp.Application, []},
      extra_applications: [:logger, :runtime_tools, :xmerl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:qr_code, "~> 3.2"},
      {:bandit, "~> 1.7"},
      {:ex_wapp, path: ex_wapp_path(), override: true}
    ]
  end

  defp ex_wapp_path do
    System.get_env("EX_WAPP_PATH", "vendor/ex_wapp")
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "tailwind demo_ex_wapp",
        "esbuild demo_ex_wapp"
      ],
      "assets.deploy": [
        "tailwind demo_ex_wapp --minify",
        "esbuild demo_ex_wapp --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "format", "test"]
    ]
  end
end
