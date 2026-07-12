defmodule DemoExWappWeb.ErrorJSON do
  @moduledoc false

  @doc "Renders an HTTP error as JSON."
  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
