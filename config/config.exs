import Config

config :demo_ex_wapp,
  generators: [timestamp_type: :utc_datetime],
  ex_wapp_store_path: Path.expand("var/ex_wapp/default.etf")

# Keep ExWapp's protocol, client identity, IQ and sync defaults intact. This demo
# exercises the library exactly as a consumer such as Isma does; overriding the
# WhatsApp Web version or capabilities here can make authentication succeed while
# later USync/prekey IQ requests are silently ignored by the server.

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
config :ex_wapp, :json_library, Jason

import_config "#{config_env()}.exs"
