defmodule DemoExWappWeb.DashboardLive do
  @moduledoc "One-page QR, chat selection, and ExWapp feature test dashboard."

  use DemoExWappWeb, :live_view

  require Logger

  alias DemoExWapp.{SessionState, WhatsApp}

  @data_tests [
    {:sync_contacts, "Synchronize contacts"},
    {:list_contacts, "List synced contacts"},
    {:list_chats, "List chat metadata"},
    {:get_messages, "Read a bounded message page"},
    {:stream_messages, "Stream chat history lazily"},
    {:all_messages, "Stream all local messages without a limit"}
  ]

  @send_tests [
    {:send_text, "Send text"},
    {:send_reply, "Reply quoting a message"},
    {:send_image, "Send image"},
    {:send_audio, "Send audio / voice note"},
    {:send_document, "Send document"},
    {:send_location, "Send GPS location"},
    {:send_contact, "Send WhatsApp contact"},
    {:send_event, "Send calendar event (optional)"}
  ]

  @receive_tests [
    {:receive_text, "Receive text reply"},
    {:receive_image, "Receive and download image"},
    {:receive_audio, "Receive, download, and play audio"},
    {:receive_document, "Receive and download document"},
    {:receive_location, "Receive and decode GPS location"},
    {:receive_contact, "Receive and decode WhatsApp contact"},
    {:receive_event, "Receive and decode calendar event (optional)"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SessionState.subscribe()

    state = SessionState.snapshot()
    Logger.info("ExWapp test dashboard mounted", connection_status: state.connection_status)

    {:ok,
     socket
     |> assign(:page_title, "ExWapp feature test")
     |> assign(:state, state)
     |> assign_target(first_chat_jid(state.chats))}
  end

  @impl true
  def handle_event("start_test", _params, socket) do
    Logger.info("Start test clicked")
    {:noreply, execute(socket, "Connection started", &WhatsApp.connect/0)}
  end

  def handle_event("disconnect", _params, socket) do
    Logger.info("Disconnect clicked")
    {:noreply, execute(socket, "Disconnected", &WhatsApp.disconnect/0)}
  end

  def handle_event("reset_pairing", _params, socket) do
    Logger.warning("Reset pairing clicked")
    {:noreply, execute(socket, "Pairing data reset", &WhatsApp.reset_pairing/0)}
  end

  def handle_event("refresh_chats", _params, socket) do
    Logger.info("Refresh chats clicked")
    {:noreply, execute(socket, "Chats refreshed", &WhatsApp.refresh_chats/0)}
  end

  def handle_event("select_chat", %{"chat_target" => %{"jid" => jid}}, socket) do
    Logger.info("Test target selected", target_jid: jid)
    {:noreply, assign_target(socket, String.trim(jid))}
  end

  def handle_event("type_target", %{"manual_target" => %{"jid" => jid}}, socket) do
    Logger.debug("Manual test target changed", target_jid: jid)
    {:noreply, assign_target(socket, String.trim(jid))}
  end

  def handle_event("run_suite", _params, %{assigns: %{selected_jid: jid}} = socket)
      when is_binary(jid) and jid != "" do
    if lid_jid?(jid) do
      Logger.warning("Run suite blocked for unresolved LID", target_jid: jid)

      {:noreply,
       put_flash(
         socket,
         :error,
         "This chat is still an unresolved LID. Refresh chats to sync its name and phone number."
       )}
    else
      Logger.info("Run suite clicked", target_jid: jid)

      {:noreply,
       execute(socket, "Automatic test suite started", fn -> WhatsApp.run_suite(jid) end)}
    end
  end

  def handle_event("run_suite", _params, socket) do
    Logger.warning("Run suite clicked without a target")
    {:noreply, put_flash(socket, :error, "Choose a chat or enter a WhatsApp JID first.")}
  end

  @impl true
  def handle_info({SessionState, :changed, state}, socket) do
    selected_jid = preserve_or_select(socket.assigns.selected_jid, state.chats)
    {:noreply, socket |> assign(:state, state) |> assign_target(selected_jid)}
  end

  def handle_info(message, socket) do
    Logger.debug("Dashboard ignored a LiveView message", message: inspect(message))
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        data_tests: @data_tests,
        send_tests: @send_tests,
        receive_tests: @receive_tests
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="dashboard">
        <header class="hero">
          <div>
            <p class="eyebrow">EXWAPP FEATURE HARNESS</p>
            <h1>WhatsApp integration test</h1>
            <p>
              Pair one device, send structured fixtures, then verify local history APIs.
            </p>
          </div>
          <div class={"status status-#{@state.connection_status}"}>
            <span></span>{@state.connection_status}
          </div>
        </header>

        <%= if @state.last_error do %>
          <section class="alert"><strong>Last error</strong><pre>{@state.last_error}</pre></section>
        <% end %>

        <section class="card connect-card">
          <div>
            <h2>1. Connect the device</h2>
            <p>
              Press Start test. If this store is not paired yet, scan the QR from WhatsApp Linked devices.
            </p>
          </div>
          <div class="actions">
            <button
              id="start-test-button"
              type="button"
              phx-click="start_test"
              phx-disable-with="Starting..."
              class="button primary"
              disabled={connect_busy?(@state.connection_status)}
            >
              Start test
            </button>
            <button id="disconnect-button" type="button" phx-click="disconnect" class="button">
              Disconnect
            </button>
            <button
              id="reset-pairing-button"
              type="button"
              phx-click="reset_pairing"
              class="button danger"
              data-confirm="Delete the saved pairing and require a new QR?"
            >
              Reset pairing
            </button>
          </div>
          <%= if @state.qr_image_src do %>
            <div class="qr-wrap">
              <div class="qr">
                <img src={@state.qr_image_src} alt="WhatsApp pairing QR code" />
              </div>
              <p>WhatsApp → Settings → Linked devices → Link a device</p>
            </div>
          <% end %>
        </section>

        <section class="card" id="target">
          <div class="section-heading">
            <div>
              <h2>2. Choose the test chat</h2>
              <p>The automatic suite sends its fixtures to this chat.</p>
            </div>
            <button
              id="refresh-chats-button"
              type="button"
              phx-click="refresh_chats"
              class="button"
              disabled={@state.connection_status != :connected}
            >
              Refresh chats
            </button>
          </div>

          <div class="target-form">
            <.form for={@chat_form} id="chat-target-form" phx-change="select_chat">
              <.input
                field={@chat_form[:jid]}
                type="select"
                label="Synced chat"
                prompt="Choose a chat…"
                options={chat_options(@state.chats)}
                disabled={@state.chats == []}
              />
            </.form>
            <.form for={@manual_form} id="manual-target-form" phx-change="type_target">
              <.input
                field={@manual_form[:jid]}
                type="text"
                label="Or enter a JID manually"
                placeholder="393331234567@s.whatsapp.net"
                phx-debounce="250"
              />
            </.form>
          </div>

          <p :if={group_jid?(@selected_jid)} class="group-warning">
            Group selected: ExWapp must fetch group metadata and build sender-key fanout before it
            reaches the media encoder. For the first media check, use a direct
            <code>@s.whatsapp.net</code>
            chat. Debug mode records the complete <code>w:g2</code>
            request lifecycle.
          </p>

          <p :if={lid_jid?(@selected_jid)} class="group-warning">
            This direct chat is still identified only by a WhatsApp LID. Refresh chats to sync the
            contact directory and resolve its name and phone number before sending.
          </p>

          <div :if={chat = selected_chat(@state.chats, @selected_jid)} class="selected-chat">
            <strong>Selected:</strong> {chat.label}
            <span :if={chat.phone_number}>+{chat.phone_number}</span>
            <small>send target: {chat.jid}</small>
          </div>

          <button
            id="run-suite-button"
            type="button"
            phx-click="run_suite"
            class="button primary wide"
            disabled={
              @state.connection_status != :connected or @state.suite_running? or
                empty?(@selected_jid) or lid_jid?(@selected_jid)
            }
          >
            Run data, history, media, GPS, contact and event suite
          </button>
        </section>

        <section class="check-grid">
          <.checklist
            title="Data and local history APIs"
            subtitle="Contacts, chat metadata, bounded pages, and lazy streams"
            tests={@data_tests}
            results={@state.tests}
          />
          <.checklist
            title="Automatic sends"
            subtitle="Marked as soon as ExWapp returns a result"
            tests={@send_tests}
            results={@state.tests}
          />
          <.checklist
            title="Replies to send from WhatsApp"
            subtitle="Reply with each type; downloads and decoding run automatically"
            tests={@receive_tests}
            results={@state.tests}
          />
        </section>

        <%= if map_size(@state.downloads) > 0 do %>
          <section class="card" id="downloads">
            <h2>Downloaded replies</h2>
            <div class="download-grid">
              <.download :for={{type, item} <- @state.downloads} type={type} item={item} />
            </div>
            <p class="hint">Decrypted files remain available in memory for ten minutes.</p>
          </section>
        <% end %>

        <section class="card logs-card">
          <div class="section-heading">
            <div>
              <h2>Recent inbound messages</h2>
              <p>Raw decoded values useful when copying an error report.</p>
            </div>
            <span class="count">{length(@state.messages)}</span>
          </div>
          <div :if={@state.messages == []} class="empty-state">No inbound messages yet.</div>
          <details :for={entry <- @state.messages} class="message-log">
            <summary>
              {entry.jid} · {format_time(entry.received_at)} · {content_label(entry.message)}
            </summary>
            <pre>{inspect(entry.message, pretty: true, limit: 60, printable_limit: 8_000)}</pre>
          </details>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :tests, :list, required: true
  attr :results, :map, required: true

  @spec checklist(map()) :: Phoenix.LiveView.Rendered.t()
  defp checklist(assigns) do
    ~H"""
    <section class="card checklist">
      <h2>{@title}</h2>
      <p>{@subtitle}</p>
      <ul>
        <li :for={{key, label} <- @tests} class={"check check-#{@results[key].status}"}>
          <span class="check-icon">{status_icon(@results[key].status)}</span>
          <span>
            <strong>{label}</strong><small :if={@results[key].detail}>{@results[key].detail}</small>
          </span>
        </li>
      </ul>
    </section>
    """
  end

  attr :type, :atom, required: true
  attr :item, :map, required: true

  @spec download(map()) :: Phoenix.LiveView.Rendered.t()
  defp download(assigns) do
    ~H"""
    <article class="download">
      <strong>{String.capitalize(to_string(@type))}</strong>
      <img :if={@type == :image} src={@item.url} alt="Downloaded WhatsApp reply" />
      <audio :if={@type == :audio} controls preload="metadata" src={@item.url}></audio>
      <a href={@item.url} target="_blank" rel="noopener">
        Open {@item.filename} ({@item.byte_size} bytes)
      </a>
    </article>
    """
  end

  @spec execute(Phoenix.LiveView.Socket.t(), String.t(), (-> term())) ::
          Phoenix.LiveView.Socket.t()
  defp execute(socket, success_message, operation) do
    case operation.() do
      :ok -> put_flash(socket, :info, success_message)
      {:ok, _value} -> put_flash(socket, :info, success_message)
      {:error, reason} -> put_flash(socket, :error, inspect(reason))
    end
  rescue
    exception ->
      Logger.error("Dashboard operation raised",
        reason: Exception.format(:error, exception, __STACKTRACE__)
      )

      put_flash(socket, :error, Exception.message(exception))
  end

  @spec first_chat_jid([map()]) :: String.t()
  defp first_chat_jid(chats) when is_list(chats) do
    case Enum.find(chats, &sendable_direct_chat?/1) do
      nil -> ""
      direct_chat -> direct_chat.jid
    end
  end

  @spec sendable_direct_chat?(map()) :: boolean()
  defp sendable_direct_chat?(chat) do
    not Map.get(chat, :is_group?, false) and not lid_jid?(chat.jid) and
      String.ends_with?(chat.jid, "@s.whatsapp.net") and chat.jid != "0@s.whatsapp.net"
  end

  @spec preserve_or_select(String.t(), [map()]) :: String.t()
  defp preserve_or_select("", chats), do: first_chat_jid(chats)

  defp preserve_or_select(selected, chats) do
    if Enum.any?(chats, &(&1.jid == selected)), do: selected, else: first_chat_jid(chats)
  end

  @spec assign_target(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_target(socket, jid) do
    socket
    |> assign(:selected_jid, jid)
    |> assign(:chat_form, to_form(%{"jid" => jid}, as: :chat_target))
    |> assign(:manual_form, to_form(%{"jid" => jid}, as: :manual_target))
  end

  @spec chat_options([map()]) :: [{String.t(), String.t()}]
  defp chat_options(chats),
    do: Enum.map(chats, &{chat_option_label(&1), &1.jid})

  @spec chat_option_label(map()) :: String.t()
  defp chat_option_label(%{is_group?: true} = chat), do: "[Group] #{chat.label} — #{chat.jid}"

  defp chat_option_label(chat) do
    number = if chat.phone_number, do: "+#{chat.phone_number}", else: nil

    ["[Direct]", chat.label, number]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  @spec selected_chat([map()], String.t()) :: map() | nil
  defp selected_chat(chats, jid), do: Enum.find(chats, &(&1.jid == jid))

  @spec group_jid?(term()) :: boolean()
  defp group_jid?(jid) when is_binary(jid), do: String.ends_with?(jid, "@g.us")
  defp group_jid?(_jid), do: false

  @spec lid_jid?(term()) :: boolean()
  defp lid_jid?(jid) when is_binary(jid),
    do: String.ends_with?(jid, ["@lid", "@hosted.lid"])

  defp lid_jid?(_jid), do: false

  @spec connect_busy?(atom()) :: boolean()
  defp connect_busy?(status),
    do: status in [:connecting, :pairing, :handshaking, :syncing, :connected, :reconnecting]

  @spec empty?(term()) :: boolean()
  defp empty?(value), do: not is_binary(value) or String.trim(value) == ""

  @spec status_icon(atom()) :: String.t()
  defp status_icon(:passed), do: "✓"
  defp status_icon(:failed), do: "×"
  defp status_icon(:blocked), do: "!"
  defp status_icon(:running), do: "…"
  defp status_icon(:pending), do: "○"

  @spec format_time(DateTime.t()) :: String.t()
  defp format_time(datetime), do: Calendar.strftime(datetime, "%H:%M:%S")

  @spec content_label(map()) :: String.t()
  defp content_label(%{media: %{type: type}}), do: to_string(type)
  defp content_label(%{location: value}) when not is_nil(value), do: "location"
  defp content_label(%{contact: value}) when not is_nil(value), do: "contact"
  defp content_label(%{event: value}) when not is_nil(value), do: "event"
  defp content_label(%{text: text}) when is_binary(text) and text != "", do: "text"
  defp content_label(_message), do: "message"
end
