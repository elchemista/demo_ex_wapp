import Config

config :demo_ex_wapp,
  generators: [timestamp_type: :utc_datetime],
  ex_wapp_store_path: Path.expand("var/ex_wapp/default.etf")

config :ex_wapp, :runtime,
  transport: [
    connect_timeout_ms: 15_000,
    recv_timeout_ms: :infinity
  ],
  signal: [session_max_age_ms: :timer.hours(3)]

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DemoExWappWeb.ErrorHTML, json: DemoExWappWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DemoExWapp.PubSub,
  live_view: [signing_salt: "demo-ex-wapp-live"]

config :esbuild,
  version: "0.25.4",
  demo_ex_wapp: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  demo_ex_wapp: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/app.css),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :session_id,
    :connection_status,
    :target_jid,
    :source_jid,
    :message_id,
    :content_type,
    :media_type,
    :test,
    :status,
    :reason,
    :detail,
    :filename,
    :bytes
  ]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
