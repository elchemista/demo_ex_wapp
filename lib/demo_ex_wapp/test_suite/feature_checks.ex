defmodule DemoExWapp.TestSuite.FeatureChecks do
  @moduledoc "Checks for ExWapp 0.1.6 media, reactions and phone history requests."

  alias DemoExWapp.WhatsApp

  @doc "Builds sends using small local MP4 and WebP fixtures."
  def media_operations(jid, api \\ WhatsApp) do
    [
      {:send_video,
       fn ->
         api.send_video(jid, fixture("test-video.mp4"),
           caption: "[demo_ex_wapp] Video test",
           mimetype: "video/mp4",
           seconds: 1,
           width: 128,
           height: 128
         )
       end},
      {:send_video_gif,
       fn ->
         api.send_video(jid, fixture("test-video.mp4"),
           mimetype: "video/mp4",
           seconds: 1,
           width: 128,
           height: 128,
           gif_playback: true
         )
       end},
      {:send_sticker,
       fn ->
         api.send_sticker(jid, fixture("test-sticker.webp"),
           mimetype: "image/webp",
           width: 512,
           height: 512
         )
       end},
      {:send_animated_sticker,
       fn ->
         api.send_sticker(jid, fixture("test-animated-sticker.webp"),
           mimetype: "image/webp",
           width: 512,
           height: 512,
           animated: true
         )
       end}
    ]
  end

  @doc "Adds and removes a reaction on one fixed message, checking both server acknowledgements."
  def reaction_roundtrip(jid, api \\ WhatsApp) do
    with {:ok, messages} <- api.get_messages(jid, limit: 50),
         {:ok, target} <- reaction_target(messages, jid),
         {:ok, add_id} <- api.send_reaction(jid, target.id, "👍", target.opts),
         {:ok, _status} <- api.await_message_ack(jid, add_id),
         {:ok, remove_id} <- api.send_reaction(jid, target.id, "", target.opts),
         {:ok, _status} <- api.await_message_ack(jid, remove_id) do
      {:verified,
       "target=#{target.id} added=#{add_id} removed=#{remove_id}; both server-acknowledged"}
    end
  end

  @doc "Requests history without interpreting an accepted request as downloaded history."
  def request_history(jid, api \\ WhatsApp) do
    with {:ok, stream} <- api.stream_messages(jid, order: :oldest_first),
         {:ok, anchor} <- history_anchor(stream),
         {:ok, id} <- api.request_history(jid, anchor, count: 50) do
      {:verified, "request_id=#{id}; request sent to phone, history import not yet verified"}
    end
  end

  @doc false
  def reaction_target(messages, jid) when is_list(messages) do
    candidates = messages |> Enum.filter(&valid_anchor?/1) |> Enum.sort_by(& &1.timestamp, :desc)
    # Prefer our own messages so the check does not overwrite a reaction on a received message.
    target = Enum.find(candidates, & &1.from_me) || List.first(candidates)

    case target do
      nil ->
        {:error, :no_reaction_target}

      %{from_me: false} = message ->
        participant = normalize_participant(Map.get(message, :participant))

        if String.ends_with?(jid, "@g.us") and is_nil(participant) do
          {:error, :missing_reaction_participant}
        else
          {:ok, %{id: message.id, opts: [from_me: false, participant: participant]}}
        end

      message ->
        {:ok, %{id: message.id, opts: [from_me: true]}}
    end
  end

  def reaction_target(_messages, _jid), do: {:error, :invalid_message_page}

  @doc false
  def history_anchor(stream) do
    case stream |> Enum.take(50) |> Enum.find(&valid_anchor?/1) do
      nil -> {:error, :no_history_anchor}
      message -> {:ok, Map.take(message, [:id, :from_me, :timestamp])}
    end
  end

  defp valid_anchor?(%{id: id, from_me: from_me, timestamp: ts} = message) do
    is_binary(id) and id != "" and not String.starts_with?(id, "history-sync-") and
      is_boolean(from_me) and is_integer(ts) and ts > 0 and
      not reaction?(message)
  end

  defp valid_anchor?(_), do: false

  defp reaction?(message),
    do:
      not is_nil(Map.get(message, :reaction)) or
        get_in(message, [:raw, :content_type]) == :reaction or
        match?(%{kind: :reaction}, Map.get(message, :content))

  defp normalize_participant(%ExWapp.JID{} = jid), do: ExWapp.JID.to_string(jid)
  defp normalize_participant(jid) when is_binary(jid) and jid != "", do: jid
  defp normalize_participant(_), do: nil
  defp fixture(name), do: {:path, Application.app_dir(:demo_ex_wapp, "priv/fixtures/#{name}")}
end
