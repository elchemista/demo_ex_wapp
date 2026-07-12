defmodule DemoExWapp.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    configure_ex_wapp_logging()

    children = [
      {Phoenix.PubSub, name: DemoExWapp.PubSub},
      {Task.Supervisor, name: DemoExWapp.TaskSupervisor},
      DemoExWapp.SessionState,
      DemoExWapp.DownloadStore,
      DemoExWapp.WhatsApp,
      DemoExWappWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: DemoExWapp.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DemoExWappWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec configure_ex_wapp_logging() :: :ok
  defp configure_ex_wapp_logging do
    debug? = Application.get_env(:demo_ex_wapp, :ex_wapp_debug, false)

    if debug? do
      Logger.put_application_level(:ex_wapp, :debug)
    end

    Logger.info("ExWapp logging configured", ex_wapp_debug: debug?)
  end
end
