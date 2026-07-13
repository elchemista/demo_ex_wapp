defmodule DemoExWapp.SessionState do
  @moduledoc """
  In-memory projection consumed by the demo LiveView.

  Pairing credentials stay in the ExWapp store. This process only keeps UI
  state, recent inbound messages, test results, and temporary media links.
  """

  use GenServer

  require Logger

  @topic "demo_ex_wapp:session"
  @max_messages 100
  @max_health_events 30

  @data_tests [
    :sync_contacts,
    :list_contacts,
    :list_chats,
    :get_messages,
    :stream_messages,
    :all_messages
  ]

  @send_tests [
    :send_text,
    :send_image,
    :send_audio,
    :send_document,
    :send_location,
    :send_contact,
    :send_event
  ]

  @receive_tests [
    :receive_text,
    :receive_image,
    :receive_audio,
    :receive_document,
    :receive_location,
    :receive_contact,
    :receive_event
  ]

  @automatic_tests @data_tests ++ @send_tests

  @type test_status :: :pending | :running | :passed | :failed | :blocked
  @type test_result :: %{
          status: test_status(),
          detail: String.t() | nil,
          updated_at: DateTime.t() | nil
        }
  @type snapshot :: map()

  @doc "Starts the state process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Subscribes the caller to state changes."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(DemoExWapp.PubSub, @topic)

  @doc "Returns the current UI snapshot."
  @spec snapshot() :: snapshot()
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @doc "Merges connection-related attributes into the snapshot."
  @spec update(map()) :: :ok
  def update(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:update, attrs})

  @doc "Stores the chats available to the test target selector."
  @spec put_chats([map()]) :: :ok
  def put_chats(chats) when is_list(chats), do: GenServer.call(__MODULE__, {:put_chats, chats})

  @doc "Resets every test result for a new target."
  @spec reset_tests(String.t()) :: :ok
  def reset_tests(jid) when is_binary(jid), do: GenServer.call(__MODULE__, {:reset_tests, jid})

  @doc "Marks one test as running, passed, or failed."
  @spec mark_test(atom(), test_status(), String.t() | nil) :: :ok
  def mark_test(test, status, detail \\ nil)
      when is_atom(test) and status in [:pending, :running, :passed, :failed, :blocked] do
    GenServer.call(__MODULE__, {:mark_test, test, status, detail})
  end

  @doc "Stores a browser URL for the most recent downloaded media of a type."
  @spec put_download(atom(), map()) :: :ok
  def put_download(type, download) when is_atom(type) and is_map(download),
    do: GenServer.call(__MODULE__, {:put_download, type, download})

  @doc "Adds one inbound message to the recent-message list."
  @spec add_message(term(), map()) :: :ok
  def add_message(jid, message) when is_map(message),
    do: GenServer.call(__MODULE__, {:add_message, jid, message})

  @doc "Adds one ExWapp health event."
  @spec add_health_event(term(), term()) :: :ok
  def add_health_event(type, metadata),
    do: GenServer.call(__MODULE__, {:add_health_event, type, metadata})

  @doc "Clears recent messages and health events without touching pairing data."
  @spec clear_activity() :: :ok
  def clear_activity, do: GenServer.call(__MODULE__, :clear_activity)

  @impl true
  def init(_opts), do: {:ok, default_snapshot()}

  @impl true
  def handle_call(:snapshot, _from, state) do
    state = normalize_snapshot(state)
    {:reply, state, state}
  end

  def handle_call({:update, attrs}, _from, state) do
    state
    |> Map.merge(attrs)
    |> reply_and_broadcast()
  end

  def handle_call({:put_chats, chats}, _from, state) do
    Logger.info("WhatsApp chats loaded", count: length(chats))
    reply_and_broadcast(%{state | chats: chats})
  end

  def handle_call({:reset_tests, jid}, _from, state) do
    Logger.info("Test checklist reset", target_jid: jid)

    state
    |> Map.merge(%{
      selected_jid: jid,
      tests: empty_tests(),
      downloads: %{},
      suite_running?: true,
      suite_started_at: DateTime.utc_now(),
      suite_finished_at: nil
    })
    |> reply_and_broadcast()
  end

  def handle_call({:mark_test, test, status, detail}, _from, state) do
    result = %{status: status, detail: detail, updated_at: DateTime.utc_now()}
    tests = Map.put(state.tests, test, result)
    suite_running? = suite_running?(tests)

    Logger.info("Test result changed", test: test, status: status, detail: detail)

    state
    |> Map.merge(%{
      tests: tests,
      suite_running?: suite_running?,
      suite_finished_at: suite_finished_at(state, suite_running?)
    })
    |> reply_and_broadcast()
  end

  def handle_call({:put_download, type, download}, _from, state) do
    Logger.info("Downloaded media exposed to UI", media_type: type, url: download.url)
    reply_and_broadcast(%{state | downloads: Map.put(state.downloads, type, download)})
  end

  def handle_call({:add_message, jid, message}, _from, state) do
    entry = %{
      ui_id: message_ui_id(message),
      jid: normalize_jid(jid),
      message: message,
      received_at: DateTime.utc_now()
    }

    next = %{state | messages: Enum.take([entry | state.messages], @max_messages)}
    reply_and_broadcast(next)
  end

  def handle_call({:add_health_event, type, metadata}, _from, state) do
    event = %{type: type, metadata: metadata, received_at: DateTime.utc_now()}
    next = %{state | health_events: Enum.take([event | state.health_events], @max_health_events)}
    reply_and_broadcast(next)
  end

  def handle_call(:clear_activity, _from, state) do
    reply_and_broadcast(%{state | messages: [], health_events: [], downloads: %{}})
  end

  @spec default_snapshot() :: snapshot()
  defp default_snapshot do
    %{
      connection_status: :idle,
      qr_svg: nil,
      last_error: nil,
      chats: [],
      selected_jid: nil,
      tests: empty_tests(),
      downloads: %{},
      suite_running?: false,
      suite_started_at: nil,
      suite_finished_at: nil,
      messages: [],
      health_events: []
    }
  end

  @spec empty_tests() :: %{atom() => test_result()}
  defp empty_tests do
    (@automatic_tests ++ @receive_tests)
    |> Map.new(fn test -> {test, %{status: :pending, detail: nil, updated_at: nil}} end)
  end

  @spec suite_running?(map()) :: boolean()
  defp suite_running?(tests) do
    Enum.any?(@automatic_tests, &(get_in(tests, [&1, :status]) in [:pending, :running]))
  end

  @spec suite_finished_at(snapshot(), boolean()) :: DateTime.t() | nil
  defp suite_finished_at(_state, true), do: nil
  defp suite_finished_at(%{suite_started_at: nil}, false), do: nil
  defp suite_finished_at(%{suite_finished_at: nil}, false), do: DateTime.utc_now()
  defp suite_finished_at(state, false), do: state.suite_finished_at

  @spec message_ui_id(map()) :: String.t()
  defp message_ui_id(message) do
    case Map.get(message, :id) do
      id when is_binary(id) and id != "" -> id
      _id -> Integer.to_string(System.unique_integer([:positive, :monotonic]))
    end
  end

  @spec normalize_jid(term()) :: String.t()
  defp normalize_jid(%ExWapp.JID{} = jid), do: ExWapp.JID.to_string(jid)
  defp normalize_jid(jid) when is_binary(jid), do: jid
  defp normalize_jid(jid), do: inspect(jid)

  @spec reply_and_broadcast(snapshot()) :: {:reply, :ok, snapshot()}
  defp reply_and_broadcast(state) do
    state = normalize_snapshot(state)
    :ok = Phoenix.PubSub.broadcast(DemoExWapp.PubSub, @topic, {__MODULE__, :changed, state})
    {:reply, :ok, state}
  end

  @spec normalize_snapshot(snapshot()) :: snapshot()
  defp normalize_snapshot(state) do
    tests = Map.merge(empty_tests(), Map.get(state, :tests, %{}))

    state
    |> Map.put_new(:chats, Map.get(state, :contacts, []))
    |> Map.put(:tests, tests)
  end
end
