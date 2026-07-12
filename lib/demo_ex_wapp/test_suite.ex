defmodule DemoExWapp.TestSuite do
  @moduledoc """
  Runs the outbound ExWapp smoke suite against one selected WhatsApp contact.

  Every operation is independent: a failed optional event does not prevent the
  remaining checks from running, and every result is written to `SessionState`.
  """

  require Logger

  alias DemoExWapp.{SessionState, WhatsApp}

  @type operation :: {atom(), (-> term())}

  @doc "Runs every outbound feature check for the selected contact."
  @spec run(String.t()) :: :ok
  def run(jid) when is_binary(jid) do
    Logger.info("Automatic ExWapp test suite started", target_jid: jid)
    :ok = SessionState.reset_tests(jid)

    jid
    |> operations()
    |> Enum.each(&run_operation(&1, jid))

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

  @spec run_operation(operation(), String.t()) :: :ok
  defp run_operation({test, operation}, jid) do
    Logger.info("ExWapp test operation started", test: test, target_jid: jid)
    :ok = SessionState.mark_test(test, :running)

    operation
    |> safely_run()
    |> record_result(test, jid)
  end

  @spec safely_run((-> term())) :: term()
  defp safely_run(operation) do
    operation.()
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @spec record_result(term(), atom(), String.t()) :: :ok
  defp record_result(:ok, test, jid), do: pass(test, jid, "ok")
  defp record_result({:ok, id}, test, jid), do: pass(test, jid, "message_id=#{id}")

  defp record_result({:error, reason}, test, jid) do
    detail = inspect(reason, limit: 30, printable_limit: 2_000)
    Logger.error("ExWapp test operation failed", test: test, target_jid: jid, reason: detail)
    SessionState.mark_test(test, :failed, detail)
  end

  defp record_result(other, test, jid) do
    detail = "Unexpected result: #{inspect(other, limit: 30, printable_limit: 2_000)}"

    Logger.error("ExWapp test operation returned an unexpected result",
      test: test,
      target_jid: jid,
      reason: detail
    )

    SessionState.mark_test(test, :failed, detail)
  end

  @spec pass(atom(), String.t(), String.t()) :: :ok
  defp pass(test, jid, detail) do
    Logger.info("ExWapp test operation passed", test: test, target_jid: jid, detail: detail)
    SessionState.mark_test(test, :passed, detail)
  end

  @spec fixture(String.t()) :: ExWapp.Media.source()
  defp fixture(name), do: {:path, Application.app_dir(:demo_ex_wapp, "priv/fixtures/#{name}")}
end
