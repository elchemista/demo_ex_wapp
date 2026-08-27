defmodule DemoExWapp.QRImage do
  @moduledoc """
  Renders pairing payloads as self-contained PNG images for the browser.

  Keeping the QR matrix inside a raster image prevents CSS or LiveView DOM
  patches from changing the SVG viewport and clipping modules.
  """

  @settings %QRCode.Render.PngSettings{scale: 10, quiet_zone: 4}
  @data_uri_prefix "data:image/png;base64,"

  @doc "Renders a pairing payload as a browser-safe PNG data URI."
  @spec data_uri(String.t()) :: {:ok, String.t()} | {:error, term()}
  def data_uri(payload) when is_binary(payload) do
    with {:ok, png} <-
           payload
           |> QRCode.create(:high)
           |> QRCode.render(:png, @settings) do
      {:ok, @data_uri_prefix <> Base.encode64(png)}
    end
  end
end
