import Config

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-demo-ex-wapp-123456789012345678901234567890",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
