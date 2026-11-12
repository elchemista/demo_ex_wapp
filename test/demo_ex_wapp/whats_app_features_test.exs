defmodule DemoExWapp.WhatsAppFeaturesTest do
  use ExUnit.Case, async: false

  alias DemoExWapp.{SessionState, WhatsApp}

  @jid "123@s.whatsapp.net"

  setup do
    original = SessionState.snapshot()
    SessionState.reset_tests(@jid)

    on_exit(fn ->
      for task <- Task.Supervisor.children(DemoExWapp.TaskSupervisor) do
        ref = Process.monitor(task)
        assert_receive {:DOWN, ^ref, :process, ^task, _reason}
      end

      SessionState.update(original)
    end)

    :ok
  end

  test "inbound reactions and removals from the selected chat are decoded" do
    for text <- ["👍", ""] do
      SessionState.mark_test(:receive_reaction, :pending)
      message = %{id: "reaction", from_me: false, reaction: %{message_id: "target", text: text}}
      deliver({:ex_wapp_message, @jid, message})
      assert SessionState.snapshot().tests.receive_reaction.status == :passed
    end
  end

  test "reactions from another chat or our own device do not pass the inbound check" do
    message = %{id: "reaction", from_me: false, reaction: %{message_id: "target", text: "👍"}}
    deliver({:ex_wapp_message, "999@s.whatsapp.net", message})
    deliver({:ex_wapp_message, @jid, %{message | from_me: true}})
    assert SessionState.snapshot().tests.receive_reaction.status == :pending
  end

  test "on-demand import is independent of sending the request" do
    event = {:ex_wapp_session, :history_sync, :completed, %{sync_type: :ON_DEMAND, messages: 12}}
    deliver(event)
    assert SessionState.snapshot().tests.receive_history.status == :pending

    SessionState.mark_test(:request_history, :passed, "sent")
    assert SessionState.snapshot().tests.receive_history.status == :pending
    deliver({:ex_wapp_session, :history_sync, :completed, %{sync_type: :FULL, messages: 50}})
    assert SessionState.snapshot().tests.receive_history.status == :pending

    deliver(event)
    assert %{status: :passed, detail: detail} = SessionState.snapshot().tests.receive_history
    assert detail =~ "12 messages"
    assert detail =~ "not correlated to a request ID"
  end

  test "an on-demand download error fails only the import check" do
    SessionState.mark_test(:request_history, :passed, "sent")
    deliver({:ex_wapp_session, :history_sync, :failed, :invalid_hash, %{sync_type: :ON_DEMAND}})

    assert %{status: :failed, detail: ":invalid_hash"} =
             SessionState.snapshot().tests.receive_history

    assert SessionState.snapshot().tests.request_history.status == :passed
  end

  test "passive inbound checks do not keep the automatic suite running" do
    for {key, _} <- SessionState.snapshot().tests,
        not String.starts_with?(Atom.to_string(key), "receive_") do
      SessionState.mark_test(key, :passed)
    end

    refute SessionState.snapshot().suite_running?
    assert SessionState.snapshot().tests.receive_history.status == :pending
    assert SessionState.snapshot().tests.receive_sticker.status == :pending
  end

  defp deliver(event) do
    send(WhatsApp, event)
    :sys.get_state(WhatsApp)
  end
end
