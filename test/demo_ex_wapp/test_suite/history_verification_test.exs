defmodule DemoExWapp.TestSuite.HistoryVerificationTest do
  use ExUnit.Case, async: true

  alias DemoExWapp.TestSuite.HistoryVerification

  test "message page passes only when the selected chat has local messages" do
    assert {:verified, "1 message in bounded page"} =
             HistoryVerification.message_page({:ok, [%{id: "message-1"}]}, "chat@s.whatsapp.net")

    assert {:error, {:empty_message_history, "chat@s.whatsapp.net"}} =
             HistoryVerification.message_page({:ok, []}, "chat@s.whatsapp.net")
  end

  test "lazy stream passes only when it yields a local message" do
    stream = Stream.map([%{id: "message-1"}], & &1)

    assert {:verified, detail} =
             HistoryVerification.lazy_stream({:ok, stream}, "stream_messages/3")

    assert detail =~ "sampled 1 local message"

    empty_stream = Stream.map([], & &1)

    assert {:error, {:empty_message_stream, "stream_messages/3"}} =
             HistoryVerification.lazy_stream({:ok, empty_stream}, "stream_messages/3")
  end

  test "lazy stream rejects materialized results" do
    assert {:error, {:expected_lazy_stream, "all_messages/3", []}} =
             HistoryVerification.lazy_stream({:ok, []}, "all_messages/3")
  end
end
