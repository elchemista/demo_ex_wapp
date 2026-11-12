defmodule DemoExWappWeb.DownloadController do
  use DemoExWappWeb, :controller

  require Logger

  alias DemoExWapp.DownloadStore

  # The MIME type comes from the sender. Only passive media that browsers render
  # without running scripts is served inline; everything else, including SVG
  # and HTML, is downloaded as an opaque attachment.
  @inline_types ~w(
    image/jpeg image/png image/gif image/webp
    audio/ogg audio/mpeg audio/mp4 audio/aac audio/webm audio/wav
    video/mp4 video/webm
  )

  @content_security_policy "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; sandbox"

  @doc "Serves short-lived, decrypted media to the local browser."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"token" => token}) do
    case DownloadStore.with_file(token, &serve(conn, &1)) do
      %Plug.Conn{} = conn ->
        conn

      :error ->
        Logger.warning("Expired or unknown media download token",
          token_prefix: String.slice(token, 0, 8)
        )

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "This media download expired. Send the media again.")
    end
  end

  # Runs while the store leases the file, so it cannot be deleted mid-response.
  @spec serve(Plug.Conn.t(), DownloadStore.file_item()) :: Plug.Conn.t()
  defp serve(conn, file) do
    {content_type, disposition} = presentation(file.content_type)

    Logger.debug("Serving downloaded WhatsApp media",
      filename: file.filename,
      content_type: content_type,
      bytes: file.byte_size
    )

    conn =
      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{file.filename}"))
      |> put_resp_header("cache-control", "private, max-age=300")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", @content_security_policy)
      |> put_resp_header("cross-origin-resource-policy", "same-origin")
      |> put_resp_header("accept-ranges", "bytes")

    case requested_range(conn, file.byte_size) do
      :full ->
        send_file(conn, 200, file.path)

      {:partial, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{file.byte_size}")
        |> send_file(206, file.path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{file.byte_size}")
        |> send_resp(416, "")
    end
  end

  @spec presentation(String.t()) :: {String.t(), String.t()}
  defp presentation(content_type) do
    [essence | _params] = String.split(content_type, ";", parts: 2)
    essence = essence |> String.trim() |> String.downcase()

    if essence in @inline_types do
      {essence, "inline"}
    else
      {"application/octet-stream", "attachment"}
    end
  end

  # Supports one byte range. Multiple ranges, malformed headers and If-Range
  # (no validators are sent, so it can never match) fall back to the full file.
  @spec requested_range(Plug.Conn.t(), non_neg_integer()) ::
          :full | {:partial, non_neg_integer(), non_neg_integer()} | :unsatisfiable
  defp requested_range(conn, size) do
    with true <- size > 0,
         [header] <- get_req_header(conn, "range"),
         [] <- get_req_header(conn, "if-range") do
      header |> parse_range() |> resolve_range(size)
    else
      _no_range -> :full
    end
  end

  @spec parse_range(String.t()) ::
          {:range, non_neg_integer(), non_neg_integer()}
          | {:from, non_neg_integer()}
          | {:suffix, non_neg_integer()}
          | :error
  defp parse_range("bytes=" <> spec) do
    with [first, last] <- String.split(spec, "-", parts: 2),
         {:ok, first} <- parse_position(first),
         {:ok, last} <- parse_position(last) do
      range_spec(first, last)
    else
      _invalid -> :error
    end
  end

  defp parse_range(_header), do: :error

  @spec parse_position(String.t()) :: {:ok, non_neg_integer() | nil} | :error
  defp parse_position(""), do: {:ok, nil}

  defp parse_position(digits) do
    if digits =~ ~r/\A\d{1,19}\z/, do: {:ok, String.to_integer(digits)}, else: :error
  end

  @spec range_spec(non_neg_integer() | nil, non_neg_integer() | nil) ::
          {:range, non_neg_integer(), non_neg_integer()}
          | {:from, non_neg_integer()}
          | {:suffix, non_neg_integer()}
          | :error
  defp range_spec(nil, nil), do: :error
  defp range_spec(nil, length), do: {:suffix, length}
  defp range_spec(first, nil), do: {:from, first}
  defp range_spec(first, last) when first <= last, do: {:range, first, last}
  defp range_spec(_first, _last), do: :error

  @spec resolve_range(term(), pos_integer()) ::
          :full | {:partial, non_neg_integer(), non_neg_integer()} | :unsatisfiable
  defp resolve_range(:error, _size), do: :full
  defp resolve_range({:suffix, 0}, _size), do: :unsatisfiable
  defp resolve_range({:suffix, length}, size), do: {:partial, max(size - length, 0), size - 1}
  defp resolve_range({:from, first}, size) when first < size, do: {:partial, first, size - 1}

  defp resolve_range({:range, first, last}, size) when first < size,
    do: {:partial, first, min(last, size - 1)}

  defp resolve_range(_spec, _size), do: :unsatisfiable
end
