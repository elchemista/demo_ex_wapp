defmodule DemoExWapp.TestSuite.FeatureChecksTest do
  use ExUnit.Case, async: true

  alias DemoExWapp.TestSuite.FeatureChecks
  alias DemoExWapp.TestSupport.FeatureAPI

  @jid "123@s.whatsapp.net"
  @group "456@g.us"
  @message %{id: "target", from_me: true, timestamp: 1_700_000_000}

  test "synthetic local history identifiers cannot become phone anchors or reaction targets" do
    synthetic = %{@message | id: "history-sync-local"}
    assert {:error, :no_history_anchor} = FeatureChecks.history_anchor([synthetic])
    assert {:error, :no_reaction_target} = FeatureChecks.reaction_target([synthetic], @jid)
  end

  test "media checks use bundled MP4 and WebP files with the correct modes" do
    operations = FeatureChecks.media_operations(@jid, FeatureAPI)

    assert Keyword.keys(operations) == [
             :send_video,
             :send_video_gif,
             :send_sticker,
             :send_animated_sticker
           ]

    for {key, operation} <- operations do
      assert {:ok, _} = operation.()
      assert_receive {:api_call, {kind, @jid, {:path, path}, opts}}
      bytes = File.read!(path)

      if key in [:send_video, :send_video_gif] do
        assert kind == :send_video
        assert <<_size::32, "ftyp", _::binary>> = bytes
        assert opts[:mimetype] == "video/mp4"
        assert opts[:seconds] == 1
        assert Keyword.get(opts, :gif_playback, false) == (key == :send_video_gif)
      else
        assert kind == :send_sticker
        assert <<"RIFF", _size::32-little, "WEBP", _::binary>> = bytes
        assert opts[:mimetype] == "image/webp"
        assert opts[:width] == 512 and opts[:height] == 512
        assert Keyword.get(opts, :animated, false) == (key == :send_animated_sticker)
        if key == :send_animated_sticker, do: assert(:binary.match(bytes, "ANIM") != :nomatch)
      end
    end
  end

  test "reaction add and removal keep the same target and wait for both acknowledgements" do
    FeatureAPI.configure(%{{:get_messages, @jid, [limit: 50]} => {:ok, [@message]}})
    assert {:verified, detail} = FeatureChecks.reaction_roundtrip(@jid, FeatureAPI)
    assert detail =~ "both server-acknowledged"
    assert_receive {:api_call, {:send_reaction, @jid, "target", "👍", [from_me: true]}}
    assert_receive {:api_call, {:await_message_ack, @jid, "add"}}
    assert_receive {:api_call, {:send_reaction, @jid, "target", "", [from_me: true]}}
    assert_receive {:api_call, {:await_message_ack, @jid, "remove"}}
  end

  test "an unacknowledged addition does not trigger a removal or pass" do
    FeatureAPI.configure(%{
      {:get_messages, @jid, [limit: 50]} => {:ok, [@message]},
      {:await_message_ack, @jid, "add"} => {:error, :ack_timeout}
    })

    assert {:error, :ack_timeout} = FeatureChecks.reaction_roundtrip(@jid, FeatureAPI)
    refute_received {:api_call, {:send_reaction, _, _, "", _}}
  end

  test "an unacknowledged removal fails the roundtrip" do
    FeatureAPI.configure(%{
      {:get_messages, @jid, [limit: 50]} => {:ok, [@message]},
      {:await_message_ack, @jid, "remove"} => {:error, :ack_timeout}
    })

    assert {:error, :ack_timeout} = FeatureChecks.reaction_roundtrip(@jid, FeatureAPI)
    assert_receive {:api_call, {:send_reaction, @jid, "target", "", _}}
  end

  test "reaction target prefers own messages and excludes reaction events" do
    incoming = %{@message | id: "incoming", from_me: false, timestamp: @message.timestamp + 1}

    reaction =
      Map.merge(@message, %{
        id: "reaction",
        reaction: %{text: "👍"},
        timestamp: @message.timestamp + 2
      })

    assert {:ok, %{id: "target", opts: [from_me: true]}} =
             FeatureChecks.reaction_target([incoming, reaction, @message], @jid)

    assert {:error, :no_reaction_target} = FeatureChecks.reaction_target([reaction, %{}], @jid)
  end

  test "group targets preserve the original participant and direction" do
    incoming =
      Map.merge(@message, %{
        from_me: false,
        participant: %ExWapp.JID{user: "123", server: "s.whatsapp.net"}
      })

    assert {:ok, %{opts: [from_me: false, participant: @jid]}} =
             FeatureChecks.reaction_target([incoming], @group)

    assert {:error, :missing_reaction_participant} =
             FeatureChecks.reaction_target([Map.delete(incoming, :participant)], @group)
  end

  test "history request uses Unix seconds and never polls the ordinary message ACK store" do
    FeatureAPI.configure(%{{:stream_messages, @jid, [order: :oldest_first]} => {:ok, [@message]}})
    assert {:verified, detail} = FeatureChecks.request_history(@jid, FeatureAPI)
    assert detail =~ "history import not yet verified"
    assert_receive {:api_call, {:request_history, @jid, @message, [count: 50]}}
    refute_received {:api_call, {:await_message_ack, _, _}}
  end

  test "history request errors propagate without reporting an import" do
    FeatureAPI.configure(%{
      {:stream_messages, @jid, [order: :oldest_first]} => {:ok, [@message]},
      {:request_history, @jid, @message, [count: 50]} => {:error, :not_connected}
    })

    assert {:error, :not_connected} = FeatureChecks.request_history(@jid, FeatureAPI)
  end

  test "missing anchors prevent sends and history scans are bounded" do
    assert {:error, :no_reaction_target} = FeatureChecks.reaction_roundtrip(@jid, FeatureAPI)
    assert {:error, :no_history_anchor} = FeatureChecks.request_history(@jid, FeatureAPI)
    refute_received {:api_call, {:send_reaction, _, _, _, _}}
    refute_received {:api_call, {:request_history, _, _, _}}

    stream =
      Stream.map(1..51, fn index ->
        if index > 50, do: flunk("read past the bounded anchor scan")
        %{id: "invalid", from_me: false, timestamp: nil}
      end)

    assert {:error, :no_history_anchor} = FeatureChecks.history_anchor(stream)

    assert {:ok, @message} =
             FeatureChecks.history_anchor([%{}, Map.put(@message, :reaction, %{}), @message])
  end
end
