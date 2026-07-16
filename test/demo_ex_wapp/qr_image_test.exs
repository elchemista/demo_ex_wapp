defmodule DemoExWapp.QRImageTest do
  use ExUnit.Case, async: true

  alias DemoExWapp.QRImage

  test "wraps the complete QR matrix in a square PNG data URI" do
    payload = String.duplicate("x", 237)

    assert {:ok, "data:image/png;base64," <> encoded} = QRImage.data_uri(payload)
    assert {:ok, png} = Base.decode64(encoded)

    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", width::32, height::32,
             _rest::binary>> = png

    assert width == height
    assert width > 0
    assert rem(width, 10) == 0
  end
end
