defmodule DemoExWappWeb do
  @moduledoc "Defines the web interface entry points used by the demo."

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Phoenix.LiveView.Router
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.Controller, only: [get_csrf_token: 0]
      import Phoenix.HTML
      import Phoenix.Component
      import DemoExWappWeb.CoreComponents
      alias DemoExWappWeb.Layouts
      alias Phoenix.LiveView.JS
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: DemoExWappWeb.Endpoint,
        router: DemoExWappWeb.Router,
        statics: DemoExWappWeb.static_paths()
    end
  end

  @doc "Returns the static paths served by the endpoint."
  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(assets favicon.ico robots.txt)

  @doc false
  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
