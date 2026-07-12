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
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  attr :flash, :map, required: true

  @doc "Renders Phoenix and LiveView connection flash messages."
  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <p :if={message = Phoenix.Flash.get(@flash, :info)} id="flash-info" class="flash flash-info">
        {message}
      </p>
      <p :if={message = Phoenix.Flash.get(@flash, :error)} id="flash-error" class="flash flash-error">
        {message}
      </p>
      <p
        id="client-error"
        class="flash flash-error"
        hidden
        phx-disconnected={JS.show(to: "#client-error")}
        phx-connected={JS.hide(to: "#client-error")}
      >
        Connection lost. Attempting to reconnect...
      </p>
      <p
        id="server-error"
        class="flash flash-error"
        hidden
        phx-disconnected={JS.show(to: "#server-error")}
        phx-connected={JS.hide(to: "#server-error")}
      >
        Server connection lost. Attempting to reconnect...
      </p>
    </div>
    """
  end

  @doc "Renders the Phoenix starter template theme toggle affordance."
  @spec theme_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <button
      id="theme-toggle"
      type="button"
      class="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-white/15 bg-white/10 text-white transition hover:-translate-y-0.5 hover:bg-white/15"
      aria-label="Toggle theme"
    >
      <.icon name="hero-sparkles" class="size-5" />
    </button>
    """
  end

  embed_templates "layouts/*"
end
