defmodule DemoExWappWeb.DownloadControllerTest do
  use DemoExWappWeb.ConnCase, async: false
  alias DemoExWapp.DownloadStore

  test "sender-provided SVG is an attachment with a sandbox and no sniffing", %{conn: conn} do
    token =
      DownloadStore.put(
        "<svg onload='alert(1)'/>",
        "../payload.svg",
        "IMAGE/SVG+XML; charset=utf-8"
      )

    conn = get(conn, ~p"/downloads/#{token}")
    assert response(conn, 200) =~ "<svg"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    assert hd(get_resp_header(conn, "content-disposition")) =~ "attachment"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert hd(get_resp_header(conn, "content-security-policy")) =~ "sandbox"
  end

  test "video supports bounded range reads and rejects an unsatisfiable range", %{conn: conn} do
    token = DownloadStore.put("0123456789", "video.mp4", "video/mp4")
    partial = conn |> put_req_header("range", "bytes=2-4") |> get(~p"/downloads/#{token}")
    assert response(partial, 206) == "234"
    assert get_resp_header(partial, "content-range") == ["bytes 2-4/10"]

    invalid = build_conn() |> put_req_header("range", "bytes=20-") |> get(~p"/downloads/#{token}")
    assert response(invalid, 416) == ""
    assert get_resp_header(invalid, "content-range") == ["bytes */10"]
  end

  test "expiry cannot remove a file while a response leases it" do
    token = DownloadStore.put("leased", "file.bin", "application/octet-stream")

    path =
      DownloadStore.with_file(token, fn file ->
        send(DownloadStore, {:expire, token})
        :sys.get_state(DownloadStore)
        assert File.read!(file.path) == "leased"
        assert DownloadStore.fetch(token) == :error
        file.path
      end)

    :sys.get_state(DownloadStore)
    refute File.exists?(path)
  end
end
