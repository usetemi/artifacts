defmodule ArtifactsWeb.JsonApiTest do
  @moduledoc """
  DESIGN.md "Agent interfaces → HTTP API": `AshJsonApi.Router` mounted at
  `/api` behind `ArtifactsWeb.Plugs.BearerAuth`, over the same
  `Artifacts.Publishing.Artifact` actions MCP exposes. Scenarios ported
  from the pre-rewrite `6f8c3ef:server/test/artifacts_web/controllers/
  api_test.exs`, reshaped for JSON:API request/response documents and
  this rewrite's actions (`wait` replaces the old submissions long-poll).
  """

  use ArtifactsWeb.ConnCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing

  defp on_app_host(conn), do: Map.put(conn, :host, "localhost")

  defp authed(conn, key) do
    conn
    |> on_app_host()
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("accept", "application/vnd.api+json")
  end

  defp attrs(conn, status) do
    body = json_response(conn, status)
    body["data"]["attributes"]
  end

  defp harness_key(user), do: harness_fixture!(user).__metadata__.plaintext_api_key

  describe "create, show, list, archive" do
    test "create, show, and list an Artifact, then archive it", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      organization = personal_organization!(user)

      create_conn =
        conn
        |> authed(key)
        |> post("/api/artifacts", %{
          "data" => %{
            "type" => "artifact",
            "attributes" => %{"title" => "Board", "html" => "<p>hi</p>"}
          }
        })

      created = json_response(create_conn, 201)
      id = created["data"]["id"]

      assert created["data"]["attributes"] == %{
               "title" => "Board",
               "current_version" => 1,
               "archived_at" => nil
             }

      show_conn = conn |> authed(key) |> get("/api/artifacts/#{id}")
      assert attrs(show_conn, 200) == created["data"]["attributes"]

      list_conn =
        conn
        |> authed(key)
        |> get("/api/artifacts?organization_id=#{organization.id}&archived=false")

      assert [%{"id" => ^id}] = json_response(list_conn, 200)["data"]

      archive_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{id}/archive", %{
          "data" => %{"type" => "artifact", "id" => id, "attributes" => %{}}
        })

      archived_attrs = attrs(archive_conn, 200)
      assert %{"archived_at" => archived_at} = archived_attrs
      assert is_binary(archived_at)

      still_listed_conn =
        conn
        |> authed(key)
        |> get("/api/artifacts?organization_id=#{organization.id}&archived=false")

      assert json_response(still_listed_conn, 200)["data"] == []

      archived_listed_conn =
        conn
        |> authed(key)
        |> get("/api/artifacts?organization_id=#{organization.id}&archived=true")

      assert [%{"id" => ^id}] = json_response(archived_listed_conn, 200)["data"]

      refused_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{id}/publish", %{
          "data" => %{"type" => "artifact", "id" => id, "attributes" => %{"html" => "<p>x</p>"}}
        })

      assert %{"errors" => [%{"code" => "archived"}]} = json_response(refused_conn, 409)
    end

    test "a non-member's request is not-found, never forbidden", %{conn: conn} do
      owner = user_fixture!()
      artifact = artifact_fixture!(owner)

      stranger = user_fixture!()
      key = harness_key(stranger)

      conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}")
      assert %{"errors" => [%{"code" => "not_found"}]} = json_response(conn, 404)
    end
  end

  describe "publish" do
    test "publish bumps the Version; a stale if_version conflicts", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      artifact = artifact_fixture!(user)

      publish_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{artifact.id}/publish", %{
          "data" => %{
            "type" => "artifact",
            "id" => artifact.id,
            "attributes" => %{"html" => "<p>2</p>"}
          }
        })

      assert %{"current_version" => 2} = attrs(publish_conn, 200)

      conflict_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{artifact.id}/publish", %{
          "data" => %{
            "type" => "artifact",
            "id" => artifact.id,
            "attributes" => %{"html" => "<p>stale</p>", "if_version" => 1}
          }
        })

      assert %{"errors" => [%{"code" => "conflict"}]} = json_response(conflict_conn, 409)
    end
  end

  describe "state" do
    test "reads and writes reduced state through the generic-action routes", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      artifact = artifact_fixture!(user)

      empty_conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/state")
      assert json_response(empty_conn, 200) == %{}

      write_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{artifact.id}/state", %{
          "data" => %{
            "type" => "artifact",
            "id" => artifact.id,
            "attributes" => %{"ops" => [%{"op" => "set", "path" => "cards.c1", "value" => "now"}]}
          }
        })

      assert %{"current_version" => 1} = attrs(write_conn, 200)

      read_conn = conn |> authed(key) |> get("/api/artifacts/#{artifact.id}/state")
      assert json_response(read_conn, 200) == %{"cards" => %{"c1" => "now"}}
    end
  end

  describe "submissions: submit and wait" do
    test "submit records a Submission; wait returns since a cursor and long-polls", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      artifact = artifact_fixture!(user)

      immediate_conn =
        conn
        |> authed(key)
        |> post("/api/artifacts/#{artifact.id}/wait", %{"data" => %{"since" => 0, "timeout" => 0}})

      assert json_response(immediate_conn, 201) == []

      submit_conn =
        conn
        |> authed(key)
        |> patch("/api/artifacts/#{artifact.id}/submit", %{
          "data" => %{
            "type" => "artifact",
            "id" => artifact.id,
            "attributes" => %{"payload" => "one"}
          }
        })

      assert %{"current_version" => 1} = attrs(submit_conn, 200)

      since_conn =
        conn
        |> authed(key)
        |> post("/api/artifacts/#{artifact.id}/wait", %{"data" => %{"since" => 0, "timeout" => 0}})

      assert [%{"payload" => "one"}] = json_response(since_conn, 201)

      task =
        Task.async(fn ->
          build_conn()
          |> authed(key)
          |> post("/api/artifacts/#{artifact.id}/wait", %{
            "data" => %{
              "since" => List.first(json_response(since_conn, 201))["id"],
              "timeout" => 5_000
            }
          })
        end)

      Process.sleep(50)
      {:ok, _} = Publishing.submit(artifact, "later", actor: user)

      blocked_conn = Task.await(task)
      assert [%{"payload" => "later"}] = json_response(blocked_conn, 201)
    end
  end

  describe "organizations" do
    test "a Harness key lists only the organizations its User belongs to", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      own_organization = personal_organization!(user)

      stranger = user_fixture!()
      _stranger_organization = personal_organization!(stranger)

      conn = conn |> authed(key) |> get("/api/organizations")

      assert [%{"id" => id}] = json_response(conn, 200)["data"]
      assert id == own_organization.id
    end

    test "an Agent key lists only its own organization", %{conn: conn} do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      key = agent_key_fixture!(agent, owner).__metadata__.plaintext_api_key

      other_owner = user_fixture!()
      _other_organization = personal_organization!(other_owner)

      conn = conn |> authed(key) |> get("/api/organizations")

      assert [%{"id" => id}] = json_response(conn, 200)["data"]
      assert id == organization.id
    end
  end

  describe "history" do
    test "returns every Event with what it describes", %{conn: conn} do
      user = user_fixture!()
      key = harness_key(user)
      artifact = artifact_fixture!(user)

      conn =
        conn
        |> authed(key)
        |> get("/api/artifacts/#{artifact.id}/history?after=0&limit=50&include_html=false")

      assert [%{"kind" => "version_published", "data" => %{"number" => 1}}] =
               json_response(conn, 200)
    end
  end
end
