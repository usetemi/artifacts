defmodule ArtifactsWeb.Api.VersionHtmlControllerTest do
  @moduledoc """
  `GET /api/artifacts/:id/versions/:n.html` (DESIGN.md "HTTP API"): the
  raw-HTML route declared ahead of the `/api` forward so it wins over
  `ArtifactsWeb.JsonApiRouter`.
  """

  use ArtifactsWeb.ConnCase, async: true

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing

  defp on_app_host(conn), do: Map.put(conn, :host, "localhost")

  defp authed(conn, key) do
    conn |> on_app_host() |> put_req_header("authorization", "Bearer #{key}")
  end

  test "returns the numbered Version's stored HTML verbatim", %{conn: conn} do
    user = user_fixture!()
    key = harness_fixture!(user).__metadata__.plaintext_api_key
    artifact = artifact_fixture!(user)
    {:ok, _} = Publishing.publish(artifact, "<p>two</p>", nil, actor: user)

    conn1 = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/versions/1.html")
    assert conn1.status == 200
    assert conn1.resp_body == html()
    assert get_resp_header(conn1, "content-type") == ["text/html; charset=utf-8"]

    conn2 = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/versions/2.html")
    assert conn2.resp_body == "<p>two</p>"
  end

  test "wins over the /api forward: not a JSON:API document", %{conn: conn} do
    user = user_fixture!()
    key = harness_fixture!(user).__metadata__.plaintext_api_key
    artifact = artifact_fixture!(user)

    conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/versions/1.html")

    refute String.starts_with?(conn.resp_body, "{")
  end

  test "404s for an unknown version number", %{conn: conn} do
    user = user_fixture!()
    key = harness_fixture!(user).__metadata__.plaintext_api_key
    artifact = artifact_fixture!(user)

    conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/versions/9.html")
    assert conn.status == 404
  end

  test "404s for a non-member, never forbidden", %{conn: conn} do
    owner = user_fixture!()
    artifact = artifact_fixture!(owner)

    stranger = user_fixture!()
    key = harness_fixture!(stranger).__metadata__.plaintext_api_key

    conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/versions/1.html")
    assert conn.status == 404
  end
end
