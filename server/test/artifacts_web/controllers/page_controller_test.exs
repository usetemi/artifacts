defmodule ArtifactsWeb.PageControllerTest do
  use ArtifactsWeb.ConnCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias ArtifactsWeb.{PageController, PageToken}

  setup %{conn: conn} do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    %{conn: Map.put(conn, :host, "127.0.0.1"), user: user, artifact: artifact}
  end

  test "serves the current Version with window.__ARTIFACT__, the runtime, and a CSP", %{
    conn: conn,
    user: user,
    artifact: artifact
  } do
    token = PageToken.sign(artifact.id, user.id)
    conn = get(conn, ~p"/a/#{artifact.id}/page?t=#{token}")
    body = html_response(conn, 200)

    assert [_, json] = Regex.run(~r/window\.__ARTIFACT__ = (.*?)<\/script>/s, body)
    payload = Jason.decode!(json)

    endpoint_port = ArtifactsWeb.Endpoint.struct_url().port

    assert payload == %{
             "id" => artifact.id,
             "version" => 1,
             "token" => token,
             "socketUrl" => "ws://127.0.0.1:#{endpoint_port}/socket",
             "appOrigin" => "http://localhost:#{endpoint_port}",
             "viewer" => %{"id" => user.id, "name" => user.name}
           }

    assert body =~
             ~s(<script src="http://127.0.0.1:#{endpoint_port}/assets/js/runtime.js"></script>)

    assert body =~ "<h1>Hi</h1>"

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors http://localhost:#{endpoint_port}"
    assert csp =~ "connect-src 'self' ws://127.0.0.1:#{endpoint_port}"

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end

  test "a page without a head still gets the runtime injected first" do
    artifact = %Artifacts.Publishing.Artifact{id: "id1", current_version: 3}
    user = %Artifacts.Accounts.User{id: Ecto.UUID.generate(), name: "Ann"}

    result = PageController.inject_runtime("<p>x</p>", artifact, "tok", user)

    assert result =~
             ~r/^<script>window\.__ARTIFACT__ = \{.*\}<\/script><script src="[^"]+"><\/script><p>x<\/p>$/
  end

  test "escapes </ in the injected JSON so page content can't close the script tag" do
    artifact = %Artifacts.Publishing.Artifact{id: "abc", current_version: 1}
    user = %Artifacts.Accounts.User{id: Ecto.UUID.generate(), name: "</script><script>evil()"}

    result = PageController.inject_runtime("<head></head>", artifact, "tok", user)

    refute result =~ "</script><script>evil()"
    assert result =~ "<\\/script><script>evil()"
  end

  test "the page route 404s on the app host", %{user: user, artifact: artifact} do
    token = PageToken.sign(artifact.id, user.id)
    conn = build_conn() |> Map.put(:host, "localhost")

    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=#{token}") end
  end

  test "an unknown artifact id is refused", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/a/missing/page?t=not-a-real-token") end
  end

  test "a tampered token is refused", %{conn: conn, artifact: artifact} do
    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=not-a-real-token") end
  end

  test "an expired token is refused", %{conn: conn, user: user, artifact: artifact} do
    token =
      Phoenix.Token.sign(
        ArtifactsWeb.Endpoint,
        "artifact page v1",
        %{artifact_id: artifact.id, user_id: user.id},
        signed_at: System.system_time(:second) - 601
      )

    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=#{token}") end
  end

  test "a token minted for a different artifact is refused", %{
    conn: conn,
    user: user,
    artifact: artifact
  } do
    other = artifact_fixture!(user)
    token = PageToken.sign(other.id, user.id)

    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=#{token}") end
  end

  test "a non-member's token is refused", %{conn: conn, artifact: artifact} do
    stranger = user_fixture!()
    token = PageToken.sign(artifact.id, stranger.id)

    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=#{token}") end
  end

  test "a missing token is refused", %{conn: conn, artifact: artifact} do
    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page") end
  end

  test "an archived artifact's page is refused", %{conn: conn, user: user, artifact: artifact} do
    token = PageToken.sign(artifact.id, user.id)
    {:ok, _} = Publishing.archive(artifact, actor: user)

    assert_error_sent 404, fn -> get(conn, ~p"/a/#{artifact.id}/page?t=#{token}") end
  end

  test "the route logs no parameters, so the token never reaches a request log" do
    assert %{log: false} =
             Phoenix.Router.route_info(ArtifactsWeb.Router, "GET", "/a/xyz/page", "127.0.0.1")
  end
end
