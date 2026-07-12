import Config

config :demo_ex_wapp,
  generators: [timestamp_type: :utc_datetime],
  ex_wapp_store_path: Path.expand("var/ex_wapp/default.etf")

config :ex_wapp, :runtime,
  transport: [
    connect_timeout_ms: 15_000,
    recv_timeout_ms: :infinity
  ],
  iq: [
    default_timeout_ms: 60_000,
    prekey_timeout_ms: 60_000,
    usync_timeout_ms: 30_000,
    group_info_timeout_ms: 15_000
  ],
  signal: [
    session_max_age_ms: :timer.hours(3)
  ],
  app_state: [
    initial_sync_enabled: false
  ],
  protocol: [
    client_version: "2.3000.1041871181",
    pairing_device_props: [
      os: "Mac OS",
      platform_type: 1,
      require_full_sync: false
    ],
    user_agent: [
      os_version: "0.1",
      manufacturer: "",
      device_name: "Desktop",
      os_build: "0.1",
      locale_language: "en",
      locale_country: "US"
    ]
  ]

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
    :bytes,
    :operation_ms,
    :target_type,
    :ex_wapp_debug,
    :result,
    :count,
    :url,
    :store_path,
    :from_me,
    :mimetype,
    :health_type,
    :metadata,
    :message,
    :task_pid,
    :code_bytes,
    :payload
  ]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
