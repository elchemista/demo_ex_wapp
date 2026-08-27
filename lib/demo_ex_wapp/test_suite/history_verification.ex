defmodule DemoExWapp.TestSuite.HistoryVerification do
  @moduledoc false

  @type verification_result :: {:verified, String.t()} | {:error, term()}

  @spec message_page({:ok, term()} | {:error, term()}, String.t()) :: verification_result()
  def message_page({:ok, [_ | _] = messages}, _jid) do
    {:verified, "#{length(messages)} #{message_label(messages)} in bounded page"}
  end

  def message_page({:ok, []}, jid), do: {:error, {:empty_message_history, jid}}
  def message_page({:ok, other}, _jid), do: {:error, {:unexpected_list, "messages", other}}
  def message_page({:error, _reason} = error, _jid), do: error

  @spec lazy_stream({:ok, term()} | {:error, term()}, String.t()) :: verification_result()
  def lazy_stream({:ok, %Stream{} = stream}, api_name) do
    case Enum.take(stream, 1) do
      [%{}] ->
        {:verified, "#{api_name} is lazy; sampled 1 local message without materializing history"}

      [] ->
        {:error, {:empty_message_stream, api_name}}

      [other] ->
        {:error, {:unexpected_stream_item, api_name, other}}
    end
  end

  def lazy_stream({:ok, other}, api_name), do: {:error, {:expected_lazy_stream, api_name, other}}
  def lazy_stream({:error, _reason} = error, _api_name), do: error

  @spec message_label([term()]) :: String.t()
  defp message_label([_message]), do: "message"
  defp message_label(_messages), do: "messages"
end
