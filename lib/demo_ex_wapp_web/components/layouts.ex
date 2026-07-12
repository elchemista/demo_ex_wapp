defmodule DemoExWappWeb.Layouts do
  @moduledoc false
  use DemoExWappWeb, :html

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Renders the application shell around a LiveView."
  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <main class="page-shell">
      <p :if={message = Phoenix.Flash.get(@flash, :info)} class="flash flash-info">{message}</p>
      <p :if={message = Phoenix.Flash.get(@flash, :error)} class="flash flash-error">{message}</p>
      {render_slot(@inner_block)}
    </main>
    """
  end

  embed_templates "layouts/*"
end
