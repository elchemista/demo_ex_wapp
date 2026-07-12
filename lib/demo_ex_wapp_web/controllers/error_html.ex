defmodule DemoExWappWeb.ErrorHTML do
  use DemoExWappWeb, :html

  @doc "Renders an HTTP error page."
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
