defmodule DemoExWappWeb.DownloadController do
  use DemoExWappWeb, :controller

  require Logger

  alias DemoExWapp.DownloadStore

  @doc "Serves short-lived, decrypted media to the local browser."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"token" => token}) do
    case DownloadStore.fetch(token) do
      {:ok, item} ->
        Logger.info("Serving downloaded WhatsApp media",
          filename: item.filename,
          content_type: item.content_type,
          bytes: byte_size(item.bytes)
        )

        disposition = if inline?(item.content_type), do: "inline", else: "attachment"

        conn
        |> put_resp_content_type(item.content_type)
        |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{item.filename}"))
        |> put_resp_header("cache-control", "private, max-age=300")
        |> send_resp(200, item.bytes)

      :error ->
        Logger.warning("Expired or unknown media download token",
          token_prefix: String.slice(token, 0, 8)
        )

        send_resp(conn, 404, "This media download expired. Send the media again.")
    end
  end

  @spec inline?(String.t()) :: boolean()
  defp inline?(content_type), do: String.starts_with?(content_type, ["image/", "audio/"])
end
