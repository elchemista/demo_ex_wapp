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
      {:phoenix, "~> 1.8.16"},
      {:phoenix_html, "~> 4.4.0"},
      {:phoenix_live_reload, "~> 1.7.0", only: :dev},
      {:phoenix_live_view, "~> 1.2.13"},
      {:lazy_html, "~> 0.1.14", only: :test},
      {:esbuild, "~> 0.10.1", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.2.0"},
      {:telemetry_poller, "~> 1.3.0"},
      {:jason, "~> 1.4.5"},
      {:qr_code, "~> 3.2.0"},
      {:bandit, "~> 1.14.1"},
      {:ex_wapp, github: "elchemista/ex_wapp", ref: "bcb713dcdfb85516a972b179830a3b97850fdf8b"}
    ]
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
