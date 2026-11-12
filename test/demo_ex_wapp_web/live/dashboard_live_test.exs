defmodule DemoExWappWeb.DashboardLiveTest do
  use DemoExWappWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias DemoExWapp.SessionState

  setup do
    original = SessionState.snapshot()
    SessionState.reset_tests("123@s.whatsapp.net")
    on_exit(fn -> SessionState.update(original) end)
    :ok
  end

  test "background updates preserve a manually entered target", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#manual-target-form", manual_target: %{jid: "987@s.whatsapp.net"})
    |> render_change()

    SessionState.update(%{last_error: "background update"})
    assert has_element?(view, "#manual-target-form input[value='987@s.whatsapp.net']")
  end

  test "dashboard exposes the new send, receive and history checks", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for check <- [
          :send_video,
          :send_video_gif,
          :send_sticker,
          :send_animated_sticker,
          :send_reaction,
          :request_history,
          :receive_video,
          :receive_sticker,
          :receive_reaction,
          :receive_history
        ] do
      assert has_element?(view, "#test-#{check}.check-pending")
    end

    SessionState.mark_test(:send_reaction, :failed, "ack timeout")
    assert has_element?(view, "#test-send_reaction.check-failed", "ack timeout")
    SessionState.mark_test(:receive_reaction, :passed, "decoded")
    assert has_element?(view, "#test-receive_reaction.check-passed", "decoded")
  end

  test "downloaded videos have controls and stickers have image previews", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    SessionState.put_download(:video, %{
      url: "/downloads/video-token",
      filename: "video.mp4",
      byte_size: 123
    })

    SessionState.put_download(:sticker, %{
      url: "/downloads/sticker-token",
      filename: "sticker.webp",
      byte_size: 456
    })

    assert has_element?(view, "#download-video video[controls][src='/downloads/video-token']")
    assert has_element?(view, "#download-sticker img[src='/downloads/sticker-token']")

    assert has_element?(
             view,
             "#download-sticker a[href='/downloads/sticker-token']",
             "sticker.webp"
           )
  end
end
