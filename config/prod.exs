import Config

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
