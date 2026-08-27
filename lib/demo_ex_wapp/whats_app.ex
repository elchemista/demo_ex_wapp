defmodule DemoExWapp.WhatsApp do
  @moduledoc """
  Owns the single ExWapp session used by the LiveView demo.

  The lifecycle and QR flow follow the production wrapper used by `isma`, while
  message-specific functions expose the structured-message and history APIs
  provided by ExWapp 0.1.2.
  """

  use GenServer

  require Logger

  alias DemoExWapp.{DownloadStore, QRImage, SessionState, TestSuite}
  alias ExWapp.Session.Supervisor, as: SessionSupervisor

  @session_id "demo"
  @ack_poll_interval_ms 50
  @ack_timeout_ms 5_000

  @doc "Starts the WhatsApp wrapper."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Starts or resumes the WhatsApp connection."
  @spec connect() :: :ok | {:error, term()}
  def connect, do: GenServer.call(__MODULE__, :connect, 60_000)

  @doc "Disconnects the active WhatsApp transport."
  @spec disconnect() :: :ok
  def disconnect, do: GenServer.call(__MODULE__, :disconnect)

  @doc "Deletes local pairing credentials and stops the active session."
  @spec reset_pairing() :: :ok | {:error, term()}
  def reset_pairing, do: GenServer.call(__MODULE__, :reset_pairing, 60_000)

  @doc "Returns the current UI state."
  @spec status() :: SessionState.snapshot()
  def status, do: SessionState.snapshot()

  @doc "Sends a text message."
  @spec send_text(String.t(), String.t()) :: :ok | {:ok, String.t()} | {:error, term()}
  def send_text(jid, text), do: with_session(&ExWapp.send_message(&1, jid, text))

  @doc "Sends a text message that quotes an earlier message of the same chat."
  @spec send_reply(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def send_reply(jid, text, opts),
    do: with_session(&ExWapp.Session.send_text(&1, jid, text, opts))

  @doc "Uploads and sends an image."
  @spec send_image(String.t(), ExWapp.Media.source(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_image(jid, source, opts), do: with_session(&ExWapp.send_image(&1, jid, source, opts))

  @doc "Uploads and sends audio or a push-to-talk voice note."
  @spec send_audio(String.t(), ExWapp.Media.source(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_audio(jid, source, opts), do: with_session(&ExWapp.send_audio(&1, jid, source, opts))

  @doc "Uploads and sends a document."
  @spec send_document(String.t(), ExWapp.Media.source(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_document(jid, source, opts),
    do: with_session(&ExWapp.send_document(&1, jid, source, opts))

  @doc "Sends a GPS location."
  @spec send_location(String.t(), number(), number(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_location(jid, latitude, longitude, opts),
    do: with_session(&ExWapp.send_location(&1, jid, latitude, longitude, opts))

  @doc "Sends one WhatsApp vCard contact."
  @spec send_contact(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_contact(jid, name, vcard, opts),
    do: with_session(&ExWapp.send_contact(&1, jid, name, vcard, opts))

  @doc "Sends an experimental WhatsApp calendar event."
  @spec send_event(String.t(), String.t(), integer() | DateTime.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_event(jid, name, start_time, opts),
    do: with_session(&ExWapp.send_event(&1, jid, name, start_time, opts))

  @doc "Waits until WhatsApp accepts or rejects one outbound message stanza."
  @spec await_message_ack(String.t(), String.t(), pos_integer()) ::
          {:ok, ExWapp.Chat.message_status()} | {:error, term()}
  def await_message_ack(jid, message_id, timeout_ms \\ @ack_timeout_ms)
      when is_binary(jid) and is_binary(message_id) and is_integer(timeout_ms) and timeout_ms > 0 do
    with_session(fn session ->
      deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
      poll_message_ack(session, jid, message_id, deadline_ms)
    end)
  end

  @doc "Downloads, verifies, and decrypts one inbound media reference."
  @spec download_media(ExWapp.Media.Ref.t()) ::
          {:ok, ExWapp.Media.Download.t()} | {:error, term()}
  def download_media(ref), do: with_session(&ExWapp.download_media(&1, ref, []))

  @doc "Synchronizes the contact collection for the active ExWapp session."
  @spec sync_contacts() :: :ok | {:error, term()}
  def sync_contacts, do: with_session(&ExWapp.sync_contacts/1)

  @doc "Returns all contacts currently available in the ExWapp store."
  @spec list_contacts() :: {:ok, [ExWapp.Contact.t()]} | {:error, term()}
  def list_contacts do
    with_session(fn session -> session |> ExWapp.list_contacts() |> tag_value() end)
  end

  @doc "Returns chat metadata without materializing each chat's message history."
  @spec list_chats() :: {:ok, [ExWapp.Chat.chat()]} | {:error, term()}
  def list_chats do
    with_session(fn session -> session |> ExWapp.list_chats() |> tag_value() end)
  end

  @doc "Returns one bounded, materialized page of locally retained chat messages."
  @spec get_messages(String.t(), keyword()) ::
          {:ok, [ExWapp.Chat.message()]} | {:error, term()}
  def get_messages(jid, opts \\ []) when is_binary(jid) and is_list(opts) do
    with_session(fn session -> session |> ExWapp.get_messages(jid, opts) |> tag_value() end)
  end

  @doc "Returns ExWapp's lazy stream over locally retained messages for one chat."
  @spec stream_messages(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_messages(jid, opts \\ []) when is_binary(jid) and is_list(opts) do
    with_session(fn session -> session |> ExWapp.stream_messages(jid, opts) |> tag_value() end)
  end

  @doc "Returns the unbounded local-history stream for one chat."
  @spec all_messages(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def all_messages(jid, opts \\ []) when is_binary(jid) and is_list(opts) do
    with_session(fn session -> session |> ExWapp.all_messages(jid, opts) |> tag_value() end)
  end

  @doc "Loads chats from the active ExWapp session into the LiveView state."
  @spec refresh_chats() :: :ok | {:error, term()}
  def refresh_chats, do: GenServer.call(__MODULE__, :refresh_chats, 70_000)

  @doc "Starts the automatic data, history, and outbound test suite in a supervised task."
  @spec run_suite(String.t()) :: :ok | {:error, term()}
  def run_suite(jid) when is_binary(jid) and jid != "" do
    GenServer.call(__MODULE__, {:run_suite, jid})
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting WhatsApp demo wrapper",
      session_id: @session_id,
      store_path: store_path()
    )

    SessionState.update(%{connection_status: :idle})
    {:ok, %{session: nil, qr_task: nil, subscribed?: false}}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    Logger.info("WhatsApp connect requested", session_id: @session_id)

    if connect_busy?(SessionState.snapshot().connection_status) do
      {:reply, :ok, state}
    else
      SessionState.update(%{connection_status: :connecting, last_error: nil})

      with {:ok, session} <- ensure_session(),
           {:ok, state} <- ensure_subscribed(state),
           :ok <- ExWapp.connect(session) do
        status = normalize_connect_status(ExWapp.state(session))
        SessionState.update(%{connection_status: status, last_error: nil})
        next = state |> Map.put(:session, session) |> start_qr_task(session)
        Logger.info("WhatsApp connect command accepted", connection_status: status)
        {:reply, :ok, next}
      else
        {:error, reason} ->
          Logger.error("WhatsApp connect failed", reason: inspect(reason))
          SessionState.update(%{connection_status: :error, last_error: inspect(reason)})
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(:disconnect, _from, state) do
    Logger.info("WhatsApp disconnect requested", session_id: @session_id)

    with {:ok, session} <- session() do
      ExWapp.disconnect(session)
    end

    SessionState.update(%{connection_status: :disconnected, qr_image_src: nil})
    {:reply, :ok, state |> cancel_qr_task() |> unsubscribe_session_events()}
  end

  def handle_call(:reset_pairing, _from, state) do
    Logger.warning("WhatsApp pairing reset requested", session_id: @session_id)

    with :ok <- stop_session(),
         :ok <- clear_store_files() do
      SessionState.update(%{
        connection_status: :idle,
        qr_image_src: nil,
        last_error: nil
      })

      next = state |> cancel_qr_task() |> unsubscribe_session_events()
      {:reply, :ok, %{next | session: nil}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:refresh_chats, _from, state) do
    Logger.info("WhatsApp chat refresh requested", session_id: @session_id)

    result =
      with_session(fn session ->
        chats = ExWapp.list_chats(session)
        contacts = maybe_sync_contacts(session, chats, ExWapp.list_contacts(session))
        normalize_chats(chats, contacts)
      end)

    case result do
      {:ok, chats} ->
        :ok = SessionState.put_chats(chats)
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("WhatsApp chat refresh failed", reason: inspect(reason))
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:run_suite, jid}, _from, state) do
    case session() do
      {:ok, _session} ->
        Logger.info("Scheduling automatic ExWapp suite", target_jid: jid)

        {:ok, _task} =
          Task.Supervisor.start_child(DemoExWapp.TaskSupervisor, fn -> TestSuite.run(jid) end)

        {:reply, :ok, state}

      :error ->
        Logger.error("Cannot schedule suite without a session", target_jid: jid)
        {:reply, {:error, :session_not_started}, state}
    end
  end

  @impl true
  def handle_info({:ex_wapp_message, jid, message}, state) do
    Logger.info("Inbound WhatsApp message received",
      source_jid: normalize_jid(jid),
      message_id: Map.get(message, :id),
      content_type: inbound_content_type(message),
      from_me: Map.get(message, :from_me, false)
    )

    SessionState.add_message(jid, message)
    schedule_chat_refresh()
    verify_inbound_message(jid, message)
    {:noreply, state}
  end

  def handle_info({:ex_wapp_session, :connected}, state) do
    Logger.info("WhatsApp session connected", session_id: @session_id)
    mark_connected()
    schedule_chat_refresh()
    {:noreply, cancel_qr_task(state)}
  end

  def handle_info({:ex_wapp_session, :connected, payload}, state) do
    status = payload_status(payload) || :connected
    SessionState.update(%{connection_status: status, qr_image_src: nil, last_error: nil})

    Logger.info("WhatsApp session state received",
      connection_status: status,
      payload: inspect(payload)
    )

    if status == :connected, do: schedule_chat_refresh()
    {:noreply, if(status == :connected, do: cancel_qr_task(state), else: state)}
  end

  def handle_info({:ex_wapp_session, :transport_ready, _payload}, state) do
    Logger.info("WhatsApp transport ready")
    SessionState.update(%{connection_status: :handshaking, last_error: nil})
    {:noreply, state}
  end

  def handle_info({:ex_wapp_session, :post_auth_ready, payload}, state) do
    status = payload_status(payload) || :connected
    SessionState.update(%{connection_status: status, qr_image_src: nil, last_error: nil})
    Logger.info("WhatsApp authentication ready", connection_status: status)
    if status == :connected, do: schedule_chat_refresh()
    {:noreply, cancel_qr_task(state)}
  end

  def handle_info({:ex_wapp_session, :initial_sync, :started, _payload}, state) do
    Logger.info("WhatsApp initial sync started")
    SessionState.update(%{connection_status: :syncing, qr_image_src: nil})
    {:noreply, cancel_qr_task(state)}
  end

  def handle_info({:ex_wapp_session, :initial_sync, :completed, _payload}, state) do
    Logger.info("WhatsApp initial sync completed")
    mark_connected()
    schedule_chat_refresh()
    {:noreply, cancel_qr_task(state)}
  end

  def handle_info({:ex_wapp_session, :initial_sync, :failed, reason, _payload}, state) do
    Logger.warning("WhatsApp initial sync failed", reason: inspect(reason))

    SessionState.update(%{
      connection_status: :connected,
      qr_image_src: nil,
      last_error: "Connected with initial sync warning: #{inspect(reason)}"
    })

    schedule_chat_refresh()
    {:noreply, cancel_qr_task(state)}
  end

  def handle_info({:ex_wapp_session, :reconnecting, reason}, state) do
    Logger.warning("WhatsApp reconnecting", reason: inspect(reason))

    SessionState.update(%{
      connection_status: :reconnecting,
      last_error: transient_disconnect_message(reason)
    })

    {:noreply, state}
  end

  def handle_info({:ex_wapp_session, :disconnected, reason}, state) do
    Logger.warning("WhatsApp disconnected", reason: inspect(reason))

    SessionState.update(%{
      connection_status: :disconnected,
      last_error: transient_disconnect_message(reason)
    })

    {:noreply, state}
  end

  def handle_info({:ex_wapp_session, :disconnected, reason, _payload}, state) do
    Logger.warning("WhatsApp disconnected", reason: inspect(reason))

    SessionState.update(%{
      connection_status: :disconnected,
      last_error: transient_disconnect_message(reason)
    })

    {:noreply, state}
  end

  def handle_info({:ex_wapp_session, :error, reason}, state) do
    Logger.error("WhatsApp session error", reason: inspect(reason))

    if reset_required?(reason) do
      reset_rejected_session(reason)
      {:noreply, %{cancel_qr_task(state) | session: nil}}
    else
      SessionState.update(%{connection_status: :error, last_error: inspect(reason)})
      {:noreply, state}
    end
  end

  def handle_info({:ex_wapp_session, :terminated, reason}, state) do
    Logger.error("WhatsApp session terminated", reason: inspect(reason))
    SessionState.update(%{connection_status: :terminated, last_error: inspect(reason)})
    {:noreply, %{cancel_qr_task(state) | session: nil}}
  end

  def handle_info({:ex_wapp_health, type, metadata}, state) do
    Logger.info("ExWapp health event", health_type: type, metadata: inspect(metadata))
    SessionState.add_health_event(type, metadata)
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug("Ignoring WhatsApp wrapper message", message: inspect(message))
    {:noreply, state}
  end

  @spec ensure_session() :: {:ok, pid()} | {:error, term()}
  defp ensure_session do
    case session() do
      {:ok, session} ->
        {:ok, session}

      :error ->
        Logger.info("Starting ExWapp session process", session_id: @session_id)
        File.mkdir_p!(Path.dirname(store_path()))

        case SessionSupervisor.start_session(@session_id,
               store: {ExWapp.Store.Ets, path: store_path()}
             ) do
          {:ok, session} -> {:ok, session}
          {:error, {:already_started, session}} -> {:ok, session}
          other -> other
        end
    end
  end

  @spec session() :: {:ok, pid()} | :error
  defp session do
    SessionSupervisor.get_session(@session_id)
  catch
    :exit, _reason -> :error
  end

  @spec with_session((pid() -> result)) :: result | {:error, :session_not_started}
        when result: term()
  defp with_session(fun) do
    case session() do
      {:ok, session} -> fun.(session)
      :error -> {:error, :session_not_started}
    end
  end

  @spec tag_value({:ok, result} | {:error, term()} | result) ::
          {:ok, result} | {:error, term()}
        when result: term()
  defp tag_value({:ok, value}), do: {:ok, value}
  defp tag_value({:error, _reason} = error), do: error
  defp tag_value(value), do: {:ok, value}

  @spec poll_message_ack(pid(), String.t(), String.t(), integer()) ::
          {:ok, ExWapp.Chat.message_status()} | {:error, term()}
  defp poll_message_ack(session, jid, message_id, deadline_ms) do
    status =
      session
      |> ExWapp.get_messages(jid, limit: 200)
      |> Enum.find_value(fn message ->
        if Map.get(message, :id) == message_id, do: Map.get(message, :status)
      end)

    case status do
      status when status in [:sent, :delivered, :read] ->
        {:ok, status}

      :failed ->
        {:error, {:server_rejected, message_id}}

      _pending_or_missing ->
        continue_ack_poll(session, jid, message_id, deadline_ms)
    end
  end

  @spec continue_ack_poll(pid(), String.t(), String.t(), integer()) ::
          {:ok, ExWapp.Chat.message_status()} | {:error, term()}
  defp continue_ack_poll(session, jid, message_id, deadline_ms) do
    if System.monotonic_time(:millisecond) >= deadline_ms do
      {:error, {:server_ack_timeout, message_id}}
    else
      Process.sleep(@ack_poll_interval_ms)
      poll_message_ack(session, jid, message_id, deadline_ms)
    end
  end

  @spec ensure_subscribed(map()) :: {:ok, map()} | {:error, term()}
  defp ensure_subscribed(%{subscribed?: true} = state), do: {:ok, state}

  defp ensure_subscribed(state) do
    with :ok <- ExWapp.subscribe(@session_id) do
      {:ok, %{state | subscribed?: true}}
    end
  end

  @spec unsubscribe_session_events(map()) :: map()
  defp unsubscribe_session_events(%{subscribed?: false} = state), do: state

  defp unsubscribe_session_events(state) do
    :ok = ExWapp.unsubscribe(@session_id)
    %{state | subscribed?: false}
  end

  @spec start_qr_task(map(), pid()) :: map()
  defp start_qr_task(state, session) do
    state = cancel_qr_task(state)

    {:ok, task} =
      Task.Supervisor.start_child(DemoExWapp.TaskSupervisor, fn ->
        session
        |> ExWapp.qr_stream()
        |> Enum.each(&handle_qr_event/1)
      end)

    Logger.info("WhatsApp QR stream started", task_pid: inspect(task))

    %{state | qr_task: task}
  end

  @spec cancel_qr_task(map()) :: map()
  defp cancel_qr_task(%{qr_task: nil} = state), do: state

  defp cancel_qr_task(%{qr_task: task} = state) when is_pid(task) do
    Task.Supervisor.terminate_child(DemoExWapp.TaskSupervisor, task)
    %{state | qr_task: nil}
  end

  @spec handle_qr_event(ExWapp.Session.qr_event()) :: :ok
  defp handle_qr_event({:code, code}) do
    Logger.info("WhatsApp QR code generated", code_bytes: byte_size(code))

    qr_image_src =
      case QRImage.data_uri(code) do
        {:ok, data_uri} ->
          data_uri

        {:error, reason} ->
          Logger.error("WhatsApp QR image rendering failed", reason: inspect(reason))
          nil
      end

    SessionState.update(%{
      connection_status: :pairing,
      qr_image_src: qr_image_src,
      last_error: nil
    })
  end

  defp handle_qr_event(:success) do
    Logger.info("WhatsApp QR pairing succeeded")
    mark_connected()
  end

  defp handle_qr_event({:error, reason}) do
    if transient_stream_reason?(reason) do
      Logger.warning("WhatsApp QR stream ended during recoverable reconnect",
        reason: inspect(reason)
      )
    else
      Logger.error("WhatsApp QR stream failed", reason: inspect(reason))

      unless SessionState.snapshot().connection_status in [
               :connected,
               :syncing,
               :handshaking,
               :reconnecting
             ] do
        SessionState.update(%{connection_status: :error, last_error: inspect(reason)})
      end
    end
  end

  @spec mark_connected() :: :ok
  defp mark_connected,
    do: SessionState.update(%{connection_status: :connected, qr_image_src: nil, last_error: nil})

  @spec payload_status(term()) :: atom() | nil
  defp payload_status(%{status: status}), do: normalize_status(status)
  defp payload_status(%{"status" => status}), do: normalize_status(status)
  defp payload_status(_payload), do: nil

  @spec normalize_status(term()) :: atom() | nil
  defp normalize_status(status)
       when status in [:connected, :syncing, :handshaking, :connecting, :pairing],
       do: status

  defp normalize_status("connected"), do: :connected
  defp normalize_status("syncing"), do: :syncing
  defp normalize_status("handshaking"), do: :handshaking
  defp normalize_status("connecting"), do: :connecting
  defp normalize_status("pairing"), do: :pairing
  defp normalize_status(_status), do: nil

  @spec normalize_connect_status(term()) :: atom()
  defp normalize_connect_status(status), do: normalize_status(status) || :connecting

  @spec connect_busy?(term()) :: boolean()
  defp connect_busy?(status),
    do: status in [:connecting, :pairing, :handshaking, :syncing, :connected, :reconnecting]

  @spec reset_required?(term()) :: boolean()
  defp reset_required?(:device_removed), do: true
  defp reset_required?({:stream_error, "401", "device_removed"}), do: true
  defp reset_required?({:connection_failure, :unauthorized, _location}), do: true
  defp reset_required?(_reason), do: false

  @spec transient_disconnect_message(term()) :: String.t() | nil
  defp transient_disconnect_message(reason) do
    if transient_stream_reason?(reason) do
      nil
    else
      inspect(reason)
    end
  end

  @spec transient_stream_reason?(term()) :: boolean()
  defp transient_stream_reason?({:stream_error, code, _detail}) when code in ["503", "515"],
    do: true

  defp transient_stream_reason?({_, nested}), do: transient_stream_reason?(nested)
  defp transient_stream_reason?({_, nested, _}), do: transient_stream_reason?(nested)
  defp transient_stream_reason?(_reason), do: false

  @spec reset_rejected_session(term()) :: :ok
  defp reset_rejected_session(reason) do
    :ok = stop_session()
    _result = clear_store_files()

    SessionState.update(%{
      connection_status: :error,
      qr_image_src: nil,
      last_error: "Stored device was rejected (#{inspect(reason)}). Connect again for a fresh QR."
    })
  end

  @spec stop_session() :: :ok
  defp stop_session do
    with {:ok, session} <- session() do
      ExWapp.disconnect(session)
    end

    case SessionSupervisor.stop_session(@session_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  @spec clear_store_files() :: :ok | {:error, term()}
  defp clear_store_files do
    paths = [store_path(), store_path() <> ".bak"]

    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case File.rm(path) do
        :ok -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec store_path() :: String.t()
  defp store_path do
    Application.fetch_env!(:demo_ex_wapp, :ex_wapp_store_path)
  end

  @spec schedule_chat_refresh() :: :ok
  defp schedule_chat_refresh do
    {:ok, _task} =
      Task.Supervisor.start_child(DemoExWapp.TaskSupervisor, fn ->
        case refresh_chats() do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Background chat refresh failed", reason: inspect(reason))
        end
      end)

    :ok
  end

  @spec maybe_sync_contacts(pid(), [ExWapp.Chat.chat()], [ExWapp.Contact.t()]) ::
          [ExWapp.Contact.t()]
  defp maybe_sync_contacts(session, chats, contacts) do
    if contact_sync_needed?(chats, contacts) do
      result = safe_sync_contacts(session)

      Logger.info("WhatsApp contact sync for chat resolution finished",
        result: inspect(result),
        count: length(contacts)
      )

      ExWapp.list_contacts(session)
    else
      contacts
    end
  end

  @spec safe_sync_contacts(pid()) :: :ok | {:error, term()}
  defp safe_sync_contacts(session) do
    ExWapp.sync_contacts(session)
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  @spec contact_sync_needed?([ExWapp.Chat.chat()], [ExWapp.Contact.t()]) :: boolean()
  defp contact_sync_needed?(chats, contacts) do
    index = contact_index(contacts)

    contacts == [] or
      Enum.any?(chats, fn chat ->
        jid = chat |> Map.get(:jid) |> normalize_jid()
        lid_jid?(jid) and not Map.has_key?(index, jid)
      end)
  end

  @spec normalize_chats(term(), term()) :: {:ok, [map()]} | {:error, term()}
  defp normalize_chats({:ok, chats}, contacts), do: normalize_chats(chats, contacts)

  defp normalize_chats(chats, contacts) when is_list(chats) and is_list(contacts) do
    index = contact_index(contacts)

    normalized =
      chats
      |> Enum.map(&normalize_chat(&1, index))
      |> Enum.reject(&(&1.jid == ""))
      |> Enum.uniq_by(& &1.jid)
      |> Enum.sort_by(& &1.last_message_timestamp, :desc)

    {:ok, normalized}
  end

  defp normalize_chats({:error, reason}, _contacts), do: {:error, reason}

  defp normalize_chats(chats, contacts),
    do: {:error, {:unexpected_chat_directory, chats, contacts}}

  @spec contact_index([ExWapp.Contact.t()]) :: %{String.t() => ExWapp.Contact.t()}
  defp contact_index(contacts) do
    Enum.reduce(contacts, %{}, fn
      %ExWapp.Contact{} = contact, index ->
        [normalize_jid(contact.jid), normalize_lid(contact.lid)]
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce(index, &Map.put(&2, &1, contact))

      _contact, index ->
        index
    end)
  end

  @spec normalize_chat(ExWapp.Chat.chat() | map(), map()) :: map()
  defp normalize_chat(%ExWapp.Chat{} = chat, contact_index) do
    chat_jid = normalize_jid(chat.jid)
    contact = Map.get(contact_index, chat_jid)
    group? = chat.is_group || false
    target_jid = target_jid(chat_jid, contact, group?)

    %{
      jid: target_jid,
      chat_jid: chat_jid,
      aliases: chat_aliases(chat_jid, target_jid, contact),
      label: chat_label(chat, contact, chat_jid),
      phone_number: contact_phone(contact, target_jid),
      unread_count: chat.unread_count || 0,
      is_group?: group?,
      last_message_timestamp: chat.last_message_timestamp || 0
    }
  end

  defp normalize_chat(other, contact_index) do
    chat_jid = other |> Map.get(:jid) |> normalize_jid()
    contact = Map.get(contact_index, chat_jid)
    group? = Map.get(other, :is_group, false)
    target_jid = target_jid(chat_jid, contact, group?)

    %{
      jid: target_jid,
      chat_jid: chat_jid,
      aliases: chat_aliases(chat_jid, target_jid, contact),
      label: other |> Map.get(:name) |> present_string() || contact_label(contact) || chat_jid,
      phone_number: contact_phone(contact, target_jid),
      unread_count: Map.get(other, :unread_count, 0),
      is_group?: group?,
      last_message_timestamp: Map.get(other, :last_message_timestamp, 0) || 0
    }
  end

  @spec target_jid(String.t(), ExWapp.Contact.t() | nil, boolean()) :: String.t()
  defp target_jid(chat_jid, _contact, true), do: chat_jid

  defp target_jid(chat_jid, %ExWapp.Contact{} = contact, false),
    do: present_string(contact.jid) || chat_jid

  defp target_jid(chat_jid, nil, false), do: chat_jid

  @spec chat_aliases(String.t(), String.t(), ExWapp.Contact.t() | nil) :: [String.t()]
  defp chat_aliases(chat_jid, target_jid, contact) do
    contact_aliases =
      case contact do
        %ExWapp.Contact{} -> [normalize_jid(contact.jid), normalize_lid(contact.lid)]
        nil -> []
      end

    [chat_jid, target_jid | contact_aliases]
    |> normalize_jid_aliases()
  end

  @spec chat_label(ExWapp.Chat.chat(), ExWapp.Contact.t() | nil, String.t()) :: String.t()
  defp chat_label(%ExWapp.Chat{} = chat, contact, chat_jid) do
    present_string(chat.name) || contact_label(contact) || unresolved_chat_label(chat_jid)
  end

  @spec contact_label(ExWapp.Contact.t() | nil) :: String.t() | nil
  defp contact_label(%ExWapp.Contact{} = contact) do
    [contact.full_name, contact.push_name, contact.first_name, contact.username]
    |> Enum.find_value(&present_string/1)
  end

  defp contact_label(nil), do: nil

  @spec contact_phone(ExWapp.Contact.t() | nil, String.t()) :: String.t() | nil
  defp contact_phone(%ExWapp.Contact{} = contact, target_jid) do
    present_string(contact.phone_number) || phone_from_jid(target_jid)
  end

  defp contact_phone(nil, target_jid), do: phone_from_jid(target_jid)

  @spec phone_from_jid(String.t()) :: String.t() | nil
  defp phone_from_jid(jid) do
    case String.split(jid, "@", parts: 2) do
      [number, "s.whatsapp.net"] when number != "" and number != "0" -> number
      _parts -> nil
    end
  end

  @spec unresolved_chat_label(String.t()) :: String.t()
  defp unresolved_chat_label(jid) do
    if lid_jid?(jid), do: "Unknown contact (#{jid})", else: jid
  end

  @spec normalize_lid(term()) :: String.t()
  defp normalize_lid(lid) when is_binary(lid) do
    lid = String.trim(lid)

    cond do
      lid == "" -> ""
      String.contains?(lid, "@") -> normalize_jid(lid)
      true -> "#{lid}@lid"
    end
  end

  defp normalize_lid(%ExWapp.JID{} = lid), do: normalize_jid(lid)
  defp normalize_lid(_lid), do: ""

  @spec lid_jid?(String.t()) :: boolean()
  defp lid_jid?(jid), do: String.ends_with?(jid, ["@lid", "@hosted.lid"])

  @spec present_string(term()) :: String.t() | nil
  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      present -> present
    end
  end

  defp present_string(_value), do: nil

  @spec verify_inbound_message(term(), map()) :: :ok
  defp verify_inbound_message(_jid, %{from_me: true}), do: :ok

  defp verify_inbound_message(jid, message) do
    snapshot = SessionState.snapshot()
    selected_jid = snapshot.selected_jid
    source_aliases = inbound_chat_aliases(jid, message)
    target_aliases = active_chat_aliases(snapshot.chats, selected_jid)

    if selected_jid not in [nil, ""] and aliases_intersect?(source_aliases, target_aliases) do
      verify_selected_message(message)
    else
      Logger.debug("Inbound message does not match the active test target",
        source_jids: inspect(source_aliases),
        target_jids: inspect(target_aliases)
      )
    end
  end

  @spec active_chat_aliases([map()], String.t() | nil) :: [String.t()]
  defp active_chat_aliases(chats, selected_jid) do
    case Enum.find(chats, &(&1.jid == selected_jid)) do
      nil -> [selected_jid]
      chat -> [chat.jid, Map.get(chat, :chat_jid) | Map.get(chat, :aliases, [])]
    end
    |> normalize_jid_aliases()
  end

  @spec inbound_chat_aliases(term(), map()) :: [String.t()]
  defp inbound_chat_aliases(jid, message) do
    source_jid = normalize_jid_alias(jid)

    if String.ends_with?(source_jid, "@g.us") do
      [source_jid]
    else
      attrs = get_in(message, [:raw, :attrs]) || %{}

      [
        source_jid,
        Map.get(attrs, "sender_pn"),
        Map.get(attrs, "sender_lid")
      ]
      |> normalize_jid_aliases()
    end
  end

  @spec aliases_intersect?([String.t()], [String.t()]) :: boolean()
  defp aliases_intersect?(source_aliases, target_aliases) do
    target_aliases = MapSet.new(target_aliases)
    Enum.any?(source_aliases, &MapSet.member?(target_aliases, &1))
  end

  @spec normalize_jid_aliases([term()]) :: [String.t()]
  defp normalize_jid_aliases(aliases) do
    aliases
    |> Enum.map(&normalize_jid_alias/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @spec normalize_jid_alias(term()) :: String.t()
  defp normalize_jid_alias(jid) do
    jid
    |> normalize_jid()
    |> String.replace(~r/:(\d+)@/, "@")
  end

  @spec verify_selected_message(map()) :: :ok
  defp verify_selected_message(message) do
    mark_received_text(message)
    mark_received_structure(:location, :receive_location, message)
    mark_received_structure(:contact, :receive_contact, message)
    mark_received_structure(:event, :receive_event, message)
    maybe_download_inbound_media(Map.get(message, :media))
  end

  @spec mark_received_text(map()) :: :ok
  defp mark_received_text(%{text: text}) when is_binary(text) and text != "" do
    SessionState.mark_test(:receive_text, :passed, "Inbound text received")
  end

  defp mark_received_text(_message), do: :ok

  @spec mark_received_structure(atom(), atom(), map()) :: :ok
  defp mark_received_structure(field, test, message) do
    case Map.get(message, field) do
      nil -> :ok
      _value -> SessionState.mark_test(test, :passed, "Inbound #{field} decoded")
    end
  end

  @spec maybe_download_inbound_media(term()) :: :ok
  defp maybe_download_inbound_media(%ExWapp.Media.Ref{} = ref) do
    Logger.info("Scheduling inbound media download", media_type: ref.type, mimetype: ref.mimetype)

    {:ok, _task} =
      Task.Supervisor.start_child(DemoExWapp.TaskSupervisor, fn -> download_and_publish(ref) end)

    :ok
  end

  defp maybe_download_inbound_media(%{ref: %ExWapp.Media.Ref{} = ref}),
    do: maybe_download_inbound_media(ref)

  defp maybe_download_inbound_media(_media), do: :ok

  @spec download_and_publish(ExWapp.Media.Ref.t()) :: :ok
  defp download_and_publish(ref) do
    Logger.info("Inbound media download started", media_type: ref.type, mimetype: ref.mimetype)

    case download_media(ref) do
      {:ok, download} -> publish_download(ref, download)
      {:error, reason} -> fail_download(ref.type, reason)
    end
  rescue
    exception -> fail_download(ref.type, {:exception, Exception.message(exception)})
  catch
    kind, reason -> fail_download(ref.type, {kind, reason})
  end

  @spec publish_download(ExWapp.Media.Ref.t(), ExWapp.Media.Download.t()) :: :ok
  defp publish_download(ref, download) do
    filename = media_filename(ref)
    content_type = download.mimetype || ref.mimetype || "application/octet-stream"
    token = DownloadStore.put(download.bytes, filename, content_type)
    test = media_receive_test(ref.type)

    Logger.info("Inbound media download passed",
      media_type: ref.type,
      filename: filename,
      content_type: content_type,
      bytes: byte_size(download.bytes)
    )

    :ok =
      SessionState.put_download(ref.type, %{
        url: "/downloads/#{token}",
        filename: filename,
        content_type: content_type,
        byte_size: byte_size(download.bytes)
      })

    SessionState.mark_test(test, :passed, "Downloaded #{byte_size(download.bytes)} bytes")
  end

  @spec fail_download(atom(), term()) :: :ok
  defp fail_download(type, reason) do
    detail = inspect(reason, limit: 30, printable_limit: 2_000)
    Logger.error("Inbound media download failed", media_type: type, reason: detail)
    SessionState.mark_test(media_receive_test(type), :failed, detail)
  end

  @spec media_receive_test(ExWapp.Media.media_type()) :: atom()
  defp media_receive_test(:image), do: :receive_image
  defp media_receive_test(:audio), do: :receive_audio
  defp media_receive_test(:document), do: :receive_document

  @spec media_filename(ExWapp.Media.Ref.t()) :: String.t()
  defp media_filename(%{type: :document, metadata: metadata}) do
    present_string(Map.get(metadata, :file_name)) || "whatsapp-document.bin"
  end

  defp media_filename(%{type: :image}), do: "whatsapp-image"
  defp media_filename(%{type: :audio}), do: "whatsapp-audio"
  defp media_filename(_ref), do: "whatsapp-media.bin"

  @spec inbound_content_type(map()) :: atom()
  defp inbound_content_type(%{media: %{type: type}}), do: type
  defp inbound_content_type(%{location: value}) when not is_nil(value), do: :location
  defp inbound_content_type(%{contact: value}) when not is_nil(value), do: :contact
  defp inbound_content_type(%{event: value}) when not is_nil(value), do: :event
  defp inbound_content_type(%{text: text}) when is_binary(text) and text != "", do: :text
  defp inbound_content_type(_message), do: :unknown

  @spec normalize_jid(term()) :: String.t()
  defp normalize_jid(%ExWapp.JID{} = jid), do: ExWapp.JID.to_string(jid)
  defp normalize_jid(jid) when is_binary(jid), do: jid
  defp normalize_jid(nil), do: ""
  defp normalize_jid(jid), do: to_string(jid)
end
