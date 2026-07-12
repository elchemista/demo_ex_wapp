defmodule DemoExWapp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
end
