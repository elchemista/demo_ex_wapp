defmodule DemoExWapp.DownloadStore do
  @moduledoc """
  Short-lived, bounded server-side storage for media downloaded from WhatsApp.

  Decrypted media is written to temporary files in a private (`0700`) directory
  instead of being kept in memory. Entries expire after ten minutes by default.
  They remain readable during that window so browser audio and video players
  and image previews can issue more than one (range) request.

  Storage is bounded by a total byte budget and an item budget. When a new
  download does not fit, the oldest idle entries are evicted. Files that are
  being served are leased through `with_file/2` and only deleted once the
  response has finished.

  Each OS process uses its own `pid-<os pid>` subdirectory of the configured
  directory. On start the store wipes that subdirectory and removes
  subdirectories left behind by earlier runs that have been untouched for
  twice the TTL. The configured directory must be dedicated to this store.

  ## Configuration

      config :demo_ex_wapp, DemoExWapp.DownloadStore,
        dir: "var/downloads",
        ttl_ms: :timer.minutes(10),
        max_bytes: 256 * 1024 * 1024,
        max_items: 64
  """

  use GenServer

  require Logger

  @default_dir "var/downloads"
  @default_ttl_ms :timer.minutes(10)
  @default_max_bytes 256 * 1024 * 1024
  @default_max_items 64
  @default_filename "whatsapp-media.bin"
  @default_content_type "application/octet-stream"
  @max_filename_bytes 200

  @type item :: %{bytes: binary(), filename: String.t(), content_type: String.t()}
  @type file_item :: %{
          path: Path.t(),
          filename: String.t(),
          content_type: String.t(),
          byte_size: non_neg_integer()
        }

  @typep entry :: %{
           path: Path.t(),
           filename: String.t(),
           content_type: String.t(),
           byte_size: non_neg_integer(),
           seq: non_neg_integer(),
           status: :pending | :ready | :expired,
           leases: non_neg_integer(),
           monitor: reference() | nil,
           timer: reference() | nil
         }
  @typep state :: %{
           dir: Path.t(),
           ttl_ms: pos_integer(),
           max_bytes: pos_integer(),
           max_items: pos_integer(),
           entries: %{String.t() => entry()},
           monitors: %{reference() => {:writer | :lease, String.t()}},
           bytes: non_neg_integer(),
           seq: non_neg_integer()
         }

  @doc "Starts the download store."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Stores one decrypted download and returns an opaque token.

  Raises when the download cannot be stored, for example because it exceeds the
  byte budget. Use `store/3` to receive an error tuple instead.
  """
  @spec put(binary(), String.t(), String.t()) :: String.t()
  def put(bytes, filename, content_type) when is_binary(bytes) do
    case store(bytes, filename, content_type) do
      {:ok, token} -> token
      {:error, reason} -> raise "could not store WhatsApp download: #{inspect(reason)}"
    end
  end

  @doc """
  Stores one decrypted download in a private temporary file.

  The file is written by the calling process so large downloads do not block
  the store.
  """
  @spec store(binary(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def store(bytes, filename, content_type) when is_binary(bytes) do
    with {:ok, token, path} <-
           GenServer.call(__MODULE__, {:reserve, byte_size(bytes), filename, content_type}) do
      write_reserved(token, path, bytes)
    end
  end

  @doc """
  Fetches one download token without consuming it.

  This reads the whole file into memory. Prefer `with_file/2` when serving it.
  """
  @spec fetch(String.t()) :: {:ok, item()} | :error
  def fetch(token) do
    with_file(token, fn file ->
      case File.read(file.path) do
        {:ok, bytes} ->
          {:ok, %{bytes: bytes, filename: file.filename, content_type: file.content_type}}

        {:error, _reason} ->
          :error
      end
    end)
  end

  @doc """
  Leases the file behind `token` while `fun` runs and returns its result.

  The file stays on disk until `fun` returns, even if the entry expires or is
  evicted meanwhile. Returns `:error` for unknown or expired tokens.
  """
  @spec with_file(String.t(), (file_item() -> result)) :: result | :error when result: term()
  def with_file(token, fun) when is_function(fun, 1) do
    case GenServer.call(__MODULE__, {:checkout, token}) do
      {:ok, file, lease} ->
        try do
          fun.(file)
        after
          GenServer.cast(__MODULE__, {:checkin, lease})
        end

      :error ->
        :error
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    config = Keyword.merge(Application.get_env(:demo_ex_wapp, __MODULE__, []), opts)
    ttl_ms = positive_integer!(config, :ttl_ms, @default_ttl_ms)
    max_bytes = positive_integer!(config, :max_bytes, @default_max_bytes)
    max_items = positive_integer!(config, :max_items, @default_max_items)
    root = Path.expand(Keyword.get(config, :dir, @default_dir))
    dir = Path.join(root, run_dir_name())

    with :ok <- ensure_private_dir(root),
         :ok <- remove_stale_run_dirs(root, 2 * ttl_ms),
         :ok <- reset_private_dir(dir) do
      {:ok,
       %{
         dir: dir,
         ttl_ms: ttl_ms,
         max_bytes: max_bytes,
         max_items: max_items,
         entries: %{},
         monitors: %{},
         bytes: 0,
         seq: 0
       }}
    else
      {:error, reason} -> {:stop, {:download_dir, reason}}
    end
  end

  @impl true
  def handle_call({:reserve, size, filename, content_type}, {pid, _tag}, state) do
    with :ok <- ensure_private_dir(state.dir),
         :ok <- check_size(size, state.max_bytes),
         {:ok, state} <- make_room(state, size) do
      token = random_id()
      path = Path.join(state.dir, random_id())
      monitor = Process.monitor(pid)

      entry = %{
        path: path,
        filename: safe_filename(filename),
        content_type: if(is_binary(content_type), do: content_type, else: @default_content_type),
        byte_size: size,
        seq: state.seq,
        status: :pending,
        leases: 0,
        monitor: monitor,
        timer: nil
      }

      state = %{
        state
        | entries: Map.put(state.entries, token, entry),
          monitors: Map.put(state.monitors, monitor, {:writer, token}),
          bytes: state.bytes + size,
          seq: state.seq + 1
      }

      {:reply, {:ok, token, path}, state}
    else
      {:full, next} -> {:reply, {:error, :store_full}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:commit, token}, _from, state) do
    case Map.fetch(state.entries, token) do
      {:ok, %{status: :pending, monitor: monitor} = entry} ->
        Process.demonitor(monitor, [:flush])
        timer = Process.send_after(self(), {:expire, token}, state.ttl_ms)
        entry = %{entry | status: :ready, monitor: nil, timer: timer}

        state = %{
          state
          | entries: Map.put(state.entries, token, entry),
            monitors: Map.delete(state.monitors, monitor)
        }

        {:reply, :ok, state}

      _other ->
        {:reply, :error, state}
    end
  end

  def handle_call({:checkout, token}, {pid, _tag}, state) do
    case Map.fetch(state.entries, token) do
      {:ok, %{status: :ready} = entry} ->
        lease = Process.monitor(pid)

        state = %{
          state
          | entries: Map.put(state.entries, token, %{entry | leases: entry.leases + 1}),
            monitors: Map.put(state.monitors, lease, {:lease, token})
        }

        {:reply, {:ok, file_item(entry), lease}, state}

      _other ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_cast({:abort, token}, state) do
    case Map.fetch(state.entries, token) do
      {:ok, %{status: :pending}} -> {:noreply, delete_entry(state, token)}
      _other -> {:noreply, state}
    end
  end

  def handle_cast({:checkin, lease}, state), do: {:noreply, release_monitor(state, lease)}

  @impl true
  def handle_info({:expire, token}, state) do
    case Map.fetch(state.entries, token) do
      {:ok, %{status: status, leases: 0}} when status in [:ready, :expired] ->
        {:noreply, delete_entry(state, token)}

      {:ok, %{status: :ready} = entry} ->
        entry = %{entry | status: :expired, timer: nil}
        {:noreply, %{state | entries: Map.put(state.entries, token, entry)}}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state),
    do: {:noreply, release_monitor(state, monitor)}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = File.rm_rf(state.dir)
    :ok
  end

  @spec write_reserved(String.t(), Path.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  defp write_reserved(token, path, bytes) do
    case File.write(path, bytes, [:exclusive]) do
      :ok ->
        case File.chmod(path, 0o600) do
          :ok ->
            commit_reserved(token, path)

          {:error, reason} ->
            GenServer.cast(__MODULE__, {:abort, token})
            {:error, {:chmod_failed, reason}}
        end

      {:error, reason} ->
        GenServer.cast(__MODULE__, {:abort, token})
        {:error, {:write_failed, reason}}
    end
  end

  defp commit_reserved(token, path) do
    case GenServer.call(__MODULE__, {:commit, token}) do
      :ok ->
        {:ok, token}

      :error ->
        # The store restarted while this file was written; nobody owns it.
        _ = File.rm(path)
        {:error, :store_restarted}
    end
  end

  @spec check_size(non_neg_integer(), pos_integer()) :: :ok | {:error, term()}
  defp check_size(size, max_bytes) when size <= max_bytes, do: :ok
  defp check_size(size, max_bytes), do: {:error, {:too_large, size, max_bytes}}

  # Evicts the oldest idle entries, but only when that is enough to fit the new
  # download. Pending and leased entries are never evicted.
  @spec make_room(state(), non_neg_integer()) ::
          {:ok, state()} | {:full, state()} | {:error, :store_full}
  defp make_room(state, size) do
    idle =
      state.entries
      |> Enum.filter(fn {_token, entry} -> entry.status == :ready and entry.leases == 0 end)
      |> Enum.sort_by(fn {_token, entry} -> entry.seq end)

    idle_bytes = Enum.reduce(idle, 0, fn {_token, entry}, acc -> acc + entry.byte_size end)

    if map_size(state.entries) - length(idle) < state.max_items and
         state.bytes - idle_bytes + size <= state.max_bytes do
      next = evict_until_fits(state, size, idle)

      if map_size(next.entries) < next.max_items and next.bytes + size <= next.max_bytes,
        do: {:ok, next},
        else: {:full, next}
    else
      {:error, :store_full}
    end
  end

  @spec evict_until_fits(state(), non_neg_integer(), [{String.t(), entry()}]) :: state()
  defp evict_until_fits(state, size, [{token, entry} | rest]) do
    if map_size(state.entries) < state.max_items and state.bytes + size <= state.max_bytes do
      state
    else
      Logger.info("Evicting downloaded WhatsApp media to stay within the storage budget",
        filename: entry.filename,
        bytes: entry.byte_size
      )

      state |> delete_entry(token) |> evict_until_fits(size, rest)
    end
  end

  defp evict_until_fits(state, _size, []), do: state

  @spec release_monitor(state(), reference()) :: state()
  defp release_monitor(state, monitor) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        state

      {{:writer, token}, monitors} ->
        Process.demonitor(monitor, [:flush])
        delete_entry(%{state | monitors: monitors}, token)

      {{:lease, token}, monitors} ->
        Process.demonitor(monitor, [:flush])
        release_lease(%{state | monitors: monitors}, token)
    end
  end

  @spec release_lease(state(), String.t()) :: state()
  defp release_lease(state, token) do
    case Map.fetch(state.entries, token) do
      {:ok, %{status: :expired, leases: 1}} ->
        delete_entry(state, token)

      {:ok, entry} ->
        %{state | entries: Map.put(state.entries, token, %{entry | leases: entry.leases - 1})}

      :error ->
        state
    end
  end

  @spec delete_entry(state(), String.t()) :: state()
  defp delete_entry(state, token) do
    case Map.pop(state.entries, token) do
      {nil, _entries} ->
        state

      {entry, entries} ->
        if entry.monitor, do: Process.demonitor(entry.monitor, [:flush])
        if entry.timer, do: Process.cancel_timer(entry.timer)

        case remove_file(entry.path) do
          :ok ->
            %{
              state
              | entries: entries,
                monitors: Map.delete(state.monitors, entry.monitor),
                bytes: state.bytes - entry.byte_size
            }

          {:error, _reason} ->
            # A failed unlink still occupies the disk budget. Keep it counted
            # and retry later instead of allowing unbounded orphan files.
            timer = Process.send_after(self(), {:expire, token}, 60_000)
            entry = %{entry | status: :expired, monitor: nil, timer: timer}

            %{
              state
              | entries: Map.put(state.entries, token, entry),
                monitors: Map.delete(state.monitors, entry.monitor)
            }
        end
    end
  end

  @spec remove_file(Path.t()) :: :ok | {:error, term()}
  defp remove_file(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not delete downloaded WhatsApp media", reason: inspect(reason))
        {:error, reason}
    end
  end

  @spec file_item(entry()) :: file_item()
  defp file_item(entry), do: Map.take(entry, [:path, :filename, :content_type, :byte_size])

  @spec run_dir_name() :: String.t()
  defp run_dir_name, do: "pid-" <> System.pid()

  # Refuses symlinks and directories owned by someone else (chmod fails).
  @spec ensure_private_dir(Path.t()) :: :ok | {:error, term()}
  defp ensure_private_dir(path) do
    with :ok <- File.mkdir_p(path),
         {:ok, %File.Stat{type: :directory}} <- File.lstat(path),
         :ok <- File.chmod(path, 0o700) do
      :ok
    else
      {:ok, %File.Stat{type: type}} -> {:error, {:not_a_directory, path, type}}
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  @spec reset_private_dir(Path.t()) :: :ok | {:error, term()}
  defp reset_private_dir(dir) do
    case File.rm_rf(dir) do
      {:ok, _removed} -> ensure_private_dir(dir)
      {:error, reason, path} -> {:error, {reason, path}}
    end
  end

  # Removes run directories of earlier OS processes. Directories of concurrent
  # processes are kept because creating or expiring a file touches their mtime.
  @spec remove_stale_run_dirs(Path.t(), pos_integer()) :: :ok | {:error, term()}
  defp remove_stale_run_dirs(root, max_age_ms) do
    cutoff = System.os_time(:second) - div(max_age_ms, 1000)
    own = run_dir_name()

    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.filter(&(&1 != own and &1 =~ ~r/\Apid-\d+\z/))
        |> Enum.reject(&live_run?/1)
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&stale_dir?(&1, cutoff))
        |> Enum.each(&File.rm_rf/1)

      {:error, reason} ->
        {:error, {reason, root}}
    end
  end

  # Never remove another live instance's directory, including a long-running
  # video lease. Without a process inventory, prefer retaining stale files.
  defp live_run?("pid-" <> pid) do
    not File.dir?("/proc") or File.exists?(Path.join("/proc", pid))
  end

  @spec stale_dir?(Path.t(), integer()) :: boolean()
  defp stale_dir?(path, cutoff) do
    case File.lstat(path, time: :posix) do
      {:ok, %File.Stat{type: :directory, mtime: mtime}} -> mtime < cutoff
      _other -> false
    end
  end

  @spec positive_integer!(keyword(), atom(), pos_integer()) :: pos_integer()
  defp positive_integer!(config, key, default) do
    case Keyword.get(config, key, default) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError, "#{inspect(key)} must be a positive integer, got: #{inspect(value)}"
    end
  end

  @spec random_id() :: String.t()
  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @spec safe_filename(term()) :: String.t()
  defp safe_filename(filename) when is_binary(filename) do
    if String.valid?(filename) do
      filename
      |> Path.basename()
      |> String.replace(~r/[^a-zA-Z0-9._-]/u, "_")
      |> truncate_filename()
      |> case do
        safe when safe in ["", ".", ".."] -> @default_filename
        safe -> safe
      end
    else
      @default_filename
    end
  end

  defp safe_filename(_filename), do: @default_filename

  # Keeps the tail so the extension survives; the name is ASCII at this point.
  @spec truncate_filename(String.t()) :: String.t()
  defp truncate_filename(name) when byte_size(name) > @max_filename_bytes,
    do: binary_part(name, byte_size(name) - @max_filename_bytes, @max_filename_bytes)

  defp truncate_filename(name), do: name
end
