defmodule DemoExWapp.SessionStateTest do
  use ExUnit.Case, async: false

  alias DemoExWapp.SessionState

  @data_tests [
    :sync_contacts,
    :list_contacts,
    :list_chats,
    :get_messages,
    :stream_messages,
    :all_messages
  ]

  test "snapshot exposes every data and local-history check" do
    tests = SessionState.snapshot().tests

    Enum.each(@data_tests, fn test ->
      assert %{status: status} = Map.fetch!(tests, test)
      assert status in [:pending, :running, :passed, :failed, :blocked]
    end)
  end

  test "snapshot exposes the QR image source instead of inline SVG" do
    snapshot = SessionState.snapshot()

    assert Map.has_key?(snapshot, :qr_image_src)
    refute Map.has_key?(snapshot, :qr_svg)
  end
end
