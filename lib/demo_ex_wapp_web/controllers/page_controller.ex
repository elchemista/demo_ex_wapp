defmodule DemoExWappWeb.PageController do
  use DemoExWappWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
