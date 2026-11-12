defmodule DemoExWapp.TestSupport.FeatureAPI do
  @moduledoc false

  def configure(responses), do: Process.put(__MODULE__, responses)

  def get_messages(jid, opts), do: call({:get_messages, jid, opts}, {:ok, []})
  def stream_messages(jid, opts), do: call({:stream_messages, jid, opts}, {:ok, []})
  def send_video(jid, source, opts), do: call({:send_video, jid, source, opts}, {:ok, "video"})

  def send_sticker(jid, source, opts),
    do: call({:send_sticker, jid, source, opts}, {:ok, "sticker"})

  def send_reaction(jid, id, text, opts) do
    call({:send_reaction, jid, id, text, opts}, {:ok, if(text == "", do: "remove", else: "add")})
  end

  def await_message_ack(jid, id), do: call({:await_message_ack, jid, id}, {:ok, :server_ack})

  def request_history(jid, anchor, opts),
    do: call({:request_history, jid, anchor, opts}, {:ok, "request"})

  defp call(request, default) do
    send(self(), {:api_call, request})
    Map.get(Process.get(__MODULE__, %{}), request, default)
  end
end
