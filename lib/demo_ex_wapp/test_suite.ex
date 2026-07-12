defmodule DemoExWapp.TestSuite do
  @moduledoc """
  Runs the outbound ExWapp smoke suite against one selected WhatsApp contact.

  Every operation is independent: a failed optional event does not prevent the
  remaining checks from running, and every result is written to `SessionState`.
  """

  require Logger

  alias DemoExWapp.{SessionState, WhatsApp}

  @type operation :: {atom(), (-> term())}
  @type operation_result :: :passed | {:failed, term()}

  @doc "Runs every outbound feature check for the selected contact."
  @spec run(String.t()) :: :ok
  def run(jid) when is_binary(jid) do
    Logger.info("Automatic ExWapp test suite started", target_jid: jid)
    :ok = SessionState.reset_tests(jid)

    [preflight | remaining] = operations(jid)

    case run_operation(preflight, jid) do
      {:failed, reason} when is_binary(jid) ->
        if group_jid?(jid) and group_preflight_failed?(reason) do
          block_group_operations(remaining, jid, reason)
        else
          Enum.each(remaining, &run_operation(&1, jid))
        end

      :passed ->
        Enum.each(remaining, &run_operation(&1, jid))
    end

    Logger.info("Automatic ExWapp test suite finished", target_jid: jid)
  end

  @spec operations(String.t()) :: [operation()]
  defp operations(jid) do
    event_start = DateTime.add(DateTime.utc_now(), 3_600, :second)

    [
      {:send_text,
       fn -> WhatsApp.send_text(jid, "[demo_ex_wapp] Text test. Reply to this chat.") end},
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
  defp record_result(:ok, test, jid) do
    :ok = pass(test, jid, "ok")
    :passed
  end

  defp record_result({:ok, id}, test, jid) do
    :ok = pass(test, jid, "message_id=#{id}")
    :passed
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

  @spec block_group_operations([operation()], String.t(), term()) :: :ok
  defp block_group_operations(operations, jid, reason) do
    detail =
      "Blocked by group metadata preflight: #{inspect(reason)}. " <>
        "Choose a direct @s.whatsapp.net chat to validate media encoding independently."

    Logger.error("Group suite blocked after text preflight",
      target_jid: jid,
      target_type: :group,
      reason: inspect(reason)
    )

    Enum.each(operations, fn {test, _operation} ->
      SessionState.mark_test(test, :blocked, detail)
    end)
  end

  @spec group_preflight_failed?(term()) :: boolean()
  defp group_preflight_failed?({:group_send_failed, _reason}), do: true
  defp group_preflight_failed?({:exit, {:timeout, {GenServer, :call, _details}}}), do: true
  defp group_preflight_failed?(_reason), do: false

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
