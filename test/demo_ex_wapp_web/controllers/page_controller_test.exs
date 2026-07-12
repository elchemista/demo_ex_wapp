defmodule DemoExWappWeb.PageControllerTest do
  use DemoExWappWeb.ConnCase

  test "GET / renders the ExWapp feature harness", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "WhatsApp integration test"
  end
end
