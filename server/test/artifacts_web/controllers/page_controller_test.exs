defmodule ArtifactsWeb.PageControllerTest do
  use ArtifactsWeb.ConnCase, async: false

  alias Artifacts.Store
  alias ArtifactsWeb.PageController

  test "the root is not a gallery", %{conn: conn} do
    assert text_response(get(conn, ~p"/"), 200) == "artifacts host\n"
  end

  test "a page is served as published, with the runtime injected and a CSP", %{conn: conn} do
    html = "<!doctype html><html><head><title>t</title></head><body>hi</body></html>"
    {:ok, artifact} = Store.create(%{title: "T", html: html})

    conn = get(conn, ~p"/a/#{artifact.id}/page")
    body = html_response(conn, 200)

    assert body =~
             ~s(<head><script src="/assets/js/runtime.js" data-artifact-id="#{artifact.id}" data-version="1"></script><title>t</title>)

    assert body =~ "<body>hi</body>"
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "connect-src 'self'"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert {:ok, %{html: ^html}} = Store.current_version(artifact.id)
  end

  test "a page without a head gets the runtime first" do
    assert PageController.inject_runtime("<p>x</p>", "id1", 3) ==
             ~s(<script src="/assets/js/runtime.js" data-artifact-id="id1" data-version="3"></script><p>x</p>)
  end

  test "unknown pages are 404", %{conn: conn} do
    assert text_response(get(conn, ~p"/a/missing/page"), 404)
  end
end
