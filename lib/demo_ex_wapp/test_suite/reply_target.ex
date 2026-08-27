defmodule DemoExWapp.TestSuite.ReplyTarget do
  @moduledoc false

  @type target :: %{
          id: String.t(),
          quoted_participant: String.t() | nil,
          label: String.t()
        }

  @doc """
  Picks the message the reply check quotes from one page of local history.

  The newest inbound message wins so the reply lands under something the tester
  just sent. When the chat only holds outbound messages the newest of those is
  quoted instead.
  """
  @spec pick({:ok, term()} | {:error, term()}, String.t()) :: {:ok, target()} | {:error, term()}
  def pick({:ok, messages}, jid) when is_list(messages) do
    case newest_quotable(messages) do
      nil -> {:error, {:no_quotable_message, jid}}
      message -> {:ok, target(message, jid)}
    end
  end

  def pick({:ok, other}, _jid), do: {:error, {:unexpected_list, "messages", other}}
  def pick({:error, _reason} = error, _jid), do: error

  @spec newest_quotable([term()]) :: map() | nil
  defp newest_quotable(messages) do
    quotable = Enum.filter(messages, &quotable?/1)
    inbound = Enum.reject(quotable, &from_me?/1)

    newest(inbound) || newest(quotable)
  end

  @spec newest([map()]) :: map() | nil
  defp newest([]), do: nil
  defp newest(messages), do: Enum.max_by(messages, &timestamp/1)

  @spec quotable?(term()) :: boolean()
  defp quotable?(message) when is_map(message) do
    case Map.get(message, :id) do
      id when is_binary(id) -> id != ""
      _id -> false
    end
  end

  defp quotable?(_message), do: false

  @spec from_me?(map()) :: boolean()
  defp from_me?(message), do: Map.get(message, :from_me) == true

  @spec timestamp(map()) :: integer()
  defp timestamp(message) do
    case Map.get(message, :timestamp) do
      timestamp when is_integer(timestamp) -> timestamp
      _other -> 0
    end
  end

  @spec target(map(), String.t()) :: target()
  defp target(message, jid) do
    id = Map.fetch!(message, :id)

    %{
      id: id,
      quoted_participant: quoted_participant(message, jid),
      label: "#{direction(message)} message #{id}"
    }
  end

  @spec direction(map()) :: String.t()
  defp direction(message), do: if(from_me?(message), do: "outgoing", else: "incoming")

  @spec quoted_participant(map(), String.t()) :: String.t() | nil
  defp quoted_participant(message, jid) do
    case normalize_jid(Map.get(message, :participant)) do
      "" -> chat_participant(message, jid)
      participant -> participant
    end
  end

  @spec chat_participant(map(), String.t()) :: String.t() | nil
  defp chat_participant(message, jid) do
    if from_me?(message) or group_jid?(jid), do: nil, else: jid
  end

  @spec group_jid?(String.t()) :: boolean()
  defp group_jid?(jid), do: String.ends_with?(jid, "@g.us")

  @spec normalize_jid(term()) :: String.t()
  defp normalize_jid(%ExWapp.JID{} = jid), do: ExWapp.JID.to_string(jid)
  defp normalize_jid(jid) when is_binary(jid), do: String.trim(jid)
  defp normalize_jid(_jid), do: ""
end
