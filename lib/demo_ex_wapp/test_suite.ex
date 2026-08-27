defmodule DemoExWapp.TestSuite do
  @moduledoc """
  Runs ExWapp data, history, and outbound smoke checks against one selected chat.

  Data checks are independent from message sending. A failed optional event does
  not prevent the remaining checks from running, and every result is written to
  `SessionState`.
  """

  require Logger

  alias DemoExWapp.{SessionState, TestSuite.HistoryVerification, TestSuite.ReplyTarget, WhatsApp}

  @type operation :: {atom(), (-> term())}
  @type operation_result :: :passed | {:failed, term()}
  @type verification_result :: {:verified, String.t()} | {:error, term()}

  @doc "Runs every data, history, and outbound feature check for the selected chat."
  @spec run(String.t()) :: :ok
  def run(jid) when is_binary(jid) do
    Logger.info("Automatic ExWapp test suite started", target_jid: jid)
    :ok = SessionState.reset_tests(jid)

    Enum.each(metadata_operations(), &run_operation(&1, jid))
    run_send_operations(send_operations(jid), jid)
    Enum.each(history_operations(jid), &run_operation(&1, jid))

    Logger.info("Automatic ExWapp test suite finished", target_jid: jid)
  end

  @spec run_send_operations([operation()], String.t()) :: :ok
  defp run_send_operations([preflight | remaining], jid) do
    case run_operation(preflight, jid) do
      {:failed, reason} when is_binary(jid) ->
        if shared_preflight_failed?(reason) do
          block_operations(remaining, jid, reason)
        else
          Enum.each(remaining, &run_operation(&1, jid))
        end

      :passed ->
        Enum.each(remaining, &run_operation(&1, jid))
    end
  end

  @spec metadata_operations() :: [operation()]
  defp metadata_operations do
    [
      {:sync_contacts, &verify_contact_sync/0},
      {:list_contacts, &verify_contacts/0},
      {:list_chats, &verify_chats/0}
    ]
  end

  @spec history_operations(String.t()) :: [operation()]
  defp history_operations(jid) do
    [
      {:get_messages, fn -> verify_message_page(jid) end},
      {:stream_messages, fn -> verify_message_stream(jid) end},
      {:all_messages, fn -> verify_all_messages_stream(jid) end}
    ]
  end

  @spec send_operations(String.t()) :: [operation()]
  defp send_operations(jid) do
    event_start = DateTime.add(DateTime.utc_now(), 3_600, :second)

    [
      {:send_text,
       fn -> WhatsApp.send_text(jid, "[demo_ex_wapp] Text test. Reply to this chat.") end},
      {:send_reply, fn -> send_quoted_reply(jid) end},
      {:send_image,
       fn ->
         WhatsApp.send_image(jid, fixture("test-image.png"),
           caption: "[demo_ex_wapp] Image send test",
           mimetype: "image/png"
         )
       end},
      {:send_audio,
       fn ->
         WhatsApp.send_audio(jid, fixture("test-audio.ogg"),
           mimetype: "audio/ogg; codecs=opus",
           ptt: true
         )
       end},
      {:send_document,
       fn ->
         WhatsApp.send_document(jid, fixture("test-document.txt"),
           caption: "[demo_ex_wapp] Document send test",
           mimetype: "text/plain",
           file_name: "ex_wapp-test-document.txt"
         )
       end},
      {:send_location,
       fn ->
         WhatsApp.send_location(jid, 45.464_211, 9.191_383,
           name: "Duomo di Milano",
           address: "Piazza del Duomo, Milano",
           comment: "[demo_ex_wapp] GPS send test"
         )
       end},
      {:send_contact,
       fn ->
         phone = "+393331234567"
         vcard = ExWapp.Contact.vcard("ExWapp Demo Contact", phone)
         WhatsApp.send_contact(jid, "ExWapp Demo Contact", vcard, [])
       end},
      {:send_event,
       fn ->
         WhatsApp.send_event(jid, "ExWapp optional event test", event_start,
           description: "Experimental WhatsApp calendar event from demo_ex_wapp",
           end_time: DateTime.add(event_start, 3_600, :second),
           location: %{
             name: "Milano",
             latitude: 45.464_211,
             longitude: 9.191_383
           }
         )
       end}
    ]
  end

  @spec send_quoted_reply(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp send_quoted_reply(jid) do
    with {:ok, target} <- jid |> WhatsApp.get_messages(limit: 20) |> ReplyTarget.pick(jid) do
      WhatsApp.send_reply(jid, "[demo_ex_wapp] Reply test quoting the #{target.label}.",
        quoted_id: target.id,
        quoted_participant: target.quoted_participant
      )
    end
  end

  @spec run_operation(operation(), String.t()) :: operation_result()
  defp run_operation({test, operation}, jid) do
    Logger.info("ExWapp test operation started", test: test, target_jid: jid)
    :ok = SessionState.mark_test(test, :running)
    started_at = System.monotonic_time(:millisecond)

    result = safely_run(operation)
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    Logger.info("ExWapp test operation completed",
      test: test,
      target_jid: jid,
      operation_ms: elapsed_ms,
      result: inspect(result, limit: 30, printable_limit: 2_000)
    )

    record_result(result, test, jid)
  end

  @spec safely_run((-> term())) :: term()
  defp safely_run(operation) do
    operation.()
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @spec record_result(term(), atom(), String.t()) :: operation_result()
  defp record_result({:verified, detail}, test, jid) do
    :ok = pass(test, jid, detail)
    :passed
  end

  defp record_result(:ok, test, jid) do
    :ok = pass(test, jid, "ok")
    :passed
  end

  defp record_result({:ok, id}, test, jid) when is_binary(id) do
    case WhatsApp.await_message_ack(jid, id) do
      {:ok, status} ->
        :ok = pass(test, jid, "message_id=#{id} server_ack=#{status}")
        :passed

      {:error, reason} ->
        detail = "message_id=#{id} #{inspect(reason)}"

        Logger.error("WhatsApp rejected or did not acknowledge test message",
          test: test,
          target_jid: jid,
          reason: detail
        )

        :ok = SessionState.mark_test(test, :failed, detail)
        {:failed, reason}
    end
  end

  defp record_result({:error, reason}, test, jid) do
    detail = inspect(reason, limit: 30, printable_limit: 2_000)
    Logger.error("ExWapp test operation failed", test: test, target_jid: jid, reason: detail)
    :ok = SessionState.mark_test(test, :failed, detail)
    {:failed, reason}
  end

  defp record_result(other, test, jid) do
    detail = "Unexpected result: #{inspect(other, limit: 30, printable_limit: 2_000)}"

    Logger.error("ExWapp test operation returned an unexpected result",
      test: test,
      target_jid: jid,
      reason: detail
    )

    :ok = SessionState.mark_test(test, :failed, detail)
    {:failed, other}
  end

  @spec verify_contact_sync() :: verification_result()
  defp verify_contact_sync do
    case WhatsApp.sync_contacts() do
      :ok -> {:verified, "Contact synchronization completed"}
      {:ok, _value} -> {:verified, "Contact synchronization completed"}
      {:error, _reason} = error -> error
      other -> {:error, {:unexpected_contact_sync_result, other}}
    end
  end

  @spec verify_contacts() :: verification_result()
  defp verify_contacts do
    verify_list(WhatsApp.list_contacts(), "contacts")
  end

  @spec verify_chats() :: verification_result()
  defp verify_chats do
    case WhatsApp.list_chats() do
      {:ok, chats} when is_list(chats) -> verify_chat_metadata(chats)
      {:ok, other} -> {:error, {:unexpected_chat_list, other}}
      {:error, _reason} = error -> error
    end
  end

  @spec verify_chat_metadata([term()]) :: verification_result()
  defp verify_chat_metadata(chats) do
    metadata_only? =
      Enum.all?(chats, fn chat ->
        is_map(chat) and not Map.has_key?(chat, :messages)
      end)

    if metadata_only? do
      {:verified, "#{length(chats)} chats; message history is stored separately"}
    else
      {:error, :chat_list_contains_embedded_message_history}
    end
  end

  @spec verify_message_page(String.t()) :: verification_result()
  defp verify_message_page(jid) do
    jid
    |> WhatsApp.get_messages(limit: 20)
    |> HistoryVerification.message_page(jid)
  end

  @spec verify_message_stream(String.t()) :: verification_result()
  defp verify_message_stream(jid) do
    jid
    |> WhatsApp.stream_messages(order: :oldest_first)
    |> HistoryVerification.lazy_stream("stream_messages/3")
  end

  @spec verify_all_messages_stream(String.t()) :: verification_result()
  defp verify_all_messages_stream(jid) do
    jid
    |> WhatsApp.all_messages(order: :oldest_first)
    |> HistoryVerification.lazy_stream("all_messages/3")
  end

  @spec verify_list({:ok, term()} | {:error, term()}, String.t()) :: verification_result()
  defp verify_list({:ok, values}, label) when is_list(values) do
    {:verified, "#{length(values)} #{label}"}
  end

  defp verify_list({:ok, other}, label), do: {:error, {:unexpected_list, label, other}}
  defp verify_list({:error, _reason} = error, _label), do: error

  @spec block_operations([operation()], String.t(), term()) :: :ok
  defp block_operations(operations, jid, reason) do
    target_type = if group_jid?(jid), do: :group, else: :direct

    detail =
      "Blocked by #{target_type} send preflight: #{inspect(reason)}. " <>
        "The remaining message types use the same device/session fanout."

    Logger.error("Suite blocked after shared send preflight",
      target_jid: jid,
      target_type: target_type,
      reason: inspect(reason)
    )

    Enum.each(operations, fn {test, _operation} ->
      SessionState.mark_test(test, :blocked, detail)
    end)
  end

  @spec shared_preflight_failed?(term()) :: boolean()
  defp shared_preflight_failed?({:group_send_failed, _reason}), do: true
  defp shared_preflight_failed?({:session_failed, _reason}), do: true
  defp shared_preflight_failed?({:unresolved_lid, _jid}), do: true
  defp shared_preflight_failed?({:not_connected, _status}), do: true
  defp shared_preflight_failed?({:send_worker_start_failed, _reason}), do: true
  defp shared_preflight_failed?({:exit, {:timeout, {GenServer, :call, _details}}}), do: true
  defp shared_preflight_failed?(_reason), do: false

  @spec group_jid?(String.t()) :: boolean()
  defp group_jid?(jid), do: String.ends_with?(jid, "@g.us")

  @spec pass(atom(), String.t(), String.t()) :: :ok
  defp pass(test, jid, detail) do
    Logger.info("ExWapp test operation passed", test: test, target_jid: jid, detail: detail)
    SessionState.mark_test(test, :passed, detail)
  end

  @spec fixture(String.t()) :: ExWapp.Media.source()
  defp fixture(name), do: {:path, Application.app_dir(:demo_ex_wapp, "priv/fixtures/#{name}")}
end
