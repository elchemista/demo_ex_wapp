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
end
