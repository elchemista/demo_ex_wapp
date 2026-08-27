import Config

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-demo-ex-wapp-please-change-in-production-1234567890",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:demo_ex_wapp, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:demo_ex_wapp, ~w(--watch)]}
  ]

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/demo_ex_wapp_web/(controllers|live|components)/.*\.(ex|heex)$",
      ~r"lib/demo_ex_wapp_web/router\.ex$"
    ]
  ]

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
