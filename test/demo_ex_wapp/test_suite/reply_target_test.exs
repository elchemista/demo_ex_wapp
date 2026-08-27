defmodule DemoExWapp.TestSuite.ReplyTargetTest do
  use ExUnit.Case, async: true

  alias DemoExWapp.TestSuite.ReplyTarget

  @chat "15550001111@s.whatsapp.net"
  @group "120363000000000000@g.us"

  test "quotes the newest inbound message of a direct chat" do
    messages = [
      %{id: "own-2", from_me: true, timestamp: 30, participant: nil},
      %{id: "peer-2", from_me: false, timestamp: 20, participant: nil},
      %{id: "peer-1", from_me: false, timestamp: 10, participant: nil}
    ]

    assert {:ok, target} = ReplyTarget.pick({:ok, messages}, @chat)
    assert target.id == "peer-2"
    assert target.quoted_participant == @chat
    assert target.label == "incoming message peer-2"
  end

  test "quotes the newest outgoing message when the chat has no inbound message" do
    messages = [
      %{id: "own-1", from_me: true, timestamp: 10, participant: nil},
      %{id: "own-2", from_me: true, timestamp: 30, participant: nil}
    ]

    assert {:ok, target} = ReplyTarget.pick({:ok, messages}, @chat)
    assert target.id == "own-2"
    assert target.label == "outgoing message own-2"
    assert target.quoted_participant == nil
  end

  test "quotes the original sender inside a group" do
    messages = [
      %{id: "group-1", from_me: false, timestamp: 10, participant: "15550002222@s.whatsapp.net"}
    ]

    assert {:ok, %{quoted_participant: "15550002222@s.whatsapp.net"}} =
             ReplyTarget.pick({:ok, messages}, @group)
  end

  test "never quotes the chat JID as the sender of a group message" do
    messages = [%{id: "group-1", from_me: false, timestamp: 10, participant: nil}]

    assert {:ok, %{id: "group-1", quoted_participant: nil}} =
             ReplyTarget.pick({:ok, messages}, @group)
  end

  test "renders a JID struct participant as a string" do
    participant = ExWapp.JID.new("15550002222", "s.whatsapp.net")
    messages = [%{id: "group-1", from_me: false, timestamp: 10, participant: participant}]

    assert {:ok, %{quoted_participant: "15550002222@s.whatsapp.net"}} =
             ReplyTarget.pick({:ok, messages}, @group)
  end

  test "skips messages that carry no usable stanza id" do
    messages = [
      %{from_me: false, timestamp: 50, participant: nil},
      %{id: "", from_me: false, timestamp: 40, participant: nil},
      %{id: "peer-1", from_me: false, timestamp: 10, participant: nil}
    ]

    assert {:ok, %{id: "peer-1"}} = ReplyTarget.pick({:ok, messages}, @chat)
  end

  test "fails when the chat holds nothing to quote" do
    assert {:error, {:no_quotable_message, @chat}} = ReplyTarget.pick({:ok, []}, @chat)

    assert {:error, {:no_quotable_message, @chat}} =
             ReplyTarget.pick({:ok, [%{from_me: false, timestamp: 10}]}, @chat)
  end

  test "passes history read failures through untouched" do
    assert {:error, :session_not_started} =
             ReplyTarget.pick({:error, :session_not_started}, @chat)

    assert {:error, {:unexpected_list, "messages", :messages}} =
             ReplyTarget.pick({:ok, :messages}, @chat)
  end
end
