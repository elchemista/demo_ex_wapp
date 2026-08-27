defmodule DemoExWappWeb.PageControllerTest do
  use DemoExWappWeb.ConnCase

  test "GET / renders the ExWapp feature harness", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "WhatsApp integration test"
    assert html =~ "List synced contacts"
    assert html =~ "List chat metadata"
    assert html =~ "Read a bounded message page"
    assert html =~ "Stream chat history lazily"
    assert html =~ "Stream all local messages without a limit"
  end
end
