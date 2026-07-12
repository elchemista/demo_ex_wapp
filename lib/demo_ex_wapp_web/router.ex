defmodule DemoExWappWeb.Router do
  use DemoExWappWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoExWappWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", DemoExWappWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    get "/downloads/:token", DownloadController, :show
  end
end
