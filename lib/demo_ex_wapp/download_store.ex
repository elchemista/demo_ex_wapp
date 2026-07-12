defmodule DemoExWapp.DownloadStore do
  @moduledoc """
  Short-lived server-side storage for media downloaded from WhatsApp.

  Entries expire after ten minutes. They remain readable during that window so
  browser audio players and image previews can issue more than one request.
  """

  use GenServer

  @ttl_ms :timer.minutes(10)

  @type item :: %{bytes: binary(), filename: String.t(), content_type: String.t()}

  @doc "Starts the download store."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Stores one decrypted download and returns an opaque token."
  @spec put(binary(), String.t(), String.t()) :: String.t()
  def put(bytes, filename, content_type) when is_binary(bytes) do
    GenServer.call(__MODULE__, {:put, bytes, filename, content_type})
  end

  @doc "Fetches one download token without consuming it."
  @spec fetch(String.t()) :: {:ok, item()} | :error
  def fetch(token), do: GenServer.call(__MODULE__, {:fetch, token})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:put, bytes, filename, content_type}, _from, state) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    Process.send_after(self(), {:expire, token}, @ttl_ms)

    item = %{
      bytes: bytes,
      filename: safe_filename(filename),
      content_type: content_type || "application/octet-stream"
    }

    {:reply, token, Map.put(state, token, item)}
  end

  def handle_call({:fetch, token}, _from, state) do
    case Map.fetch(state, token) do
      :error -> {:reply, :error, state}
      {:ok, item} -> {:reply, {:ok, item}, state}
    end
  end

  @impl true
  def handle_info({:expire, token}, state), do: {:noreply, Map.delete(state, token)}

  @spec safe_filename(String.t()) :: String.t()
  defp safe_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/u, "_")
    |> case do
      "" -> "whatsapp-media.bin"
      safe -> safe
    end
  end
end
