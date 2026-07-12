import Config

ex_wapp_debug =
  System.get_env("EX_WAPP_DEBUG", if(config_env() == :dev, do: "true", else: "false"))
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

log_level =
  case {ex_wapp_debug, String.downcase(System.get_env("DEMO_LOG_LEVEL", "info"))} do
    {true, _level} -> :debug
    {false, "debug"} -> :debug
    {false, "warning"} -> :warning
    {false, "error"} -> :error
    {false, _level} -> :info
  end

config :logger, level: log_level
config :demo_ex_wapp, ex_wapp_debug: ex_wapp_debug

if System.get_env("PHX_SERVER") do
  config :demo_ex_wapp, DemoExWappWeb.Endpoint, server: true
end

config :demo_ex_wapp,
  ex_wapp_store_path: System.get_env("EX_WAPP_STORE_PATH", Path.expand("var/ex_wapp/default.etf"))

config :demo_ex_wapp, DemoExWappWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is missing. Generate one with: mix phx.gen.secret"

  host = System.get_env("PHX_HOST", "localhost")

  config :demo_ex_wapp, DemoExWappWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
