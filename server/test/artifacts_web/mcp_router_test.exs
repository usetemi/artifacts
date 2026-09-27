defmodule ArtifactsWeb.McpRouterTest do
  @moduledoc """
  DESIGN.md "Agent interfaces → MCP": `AshAi.Mcp.Router` mounted at `/mcp`
  behind `ArtifactsWeb.Plugs.BearerAuth`. These tests exercise the real
  bearer-key pipeline (never `Ash.PlugHelpers` shortcuts on the test conn)
  and the initialize-based protocol revision (2025-06-18), which is what
  Claude Code and Codex speak by default.
  """

  use ArtifactsWeb.ConnCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing

  @mcp_path "/mcp"

  @tool_names ~w(
    list_organizations list_artifacts get_artifact publish_artifact
    get_state change_state submit wait history
    rename_artifact archive_artifact unarchive_artifact
  )

  defp on_app_host(conn), do: Map.put(conn, :host, "localhost")

  defp mcp_post(conn, method, params, opts \\ []) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => Keyword.get(opts, :id, 1),
      "method" => method,
      "params" => params
    }

    conn = conn |> on_app_host() |> put_req_header("content-type", "application/json")

    conn =
      case Keyword.get(opts, :bearer) do
        nil -> conn
        token -> put_req_header(conn, "authorization", "Bearer #{token}")
      end

    conn =
      case Keyword.get(opts, :session_id) do
        nil -> conn
        session_id -> put_req_header(conn, "mcp-session-id", session_id)
      end

    post(conn, @mcp_path, body)
  end

  defp initialize(conn, bearer) do
    init_conn =
      mcp_post(conn, "initialize", %{"protocolVersion" => "2025-06-18", "capabilities" => %{}},
        bearer: bearer
      )

    [session_id] = get_resp_header(init_conn, "mcp-session-id")
    {init_conn, session_id}
  end

  defp tools_list(conn, bearer, session_id) do
    conn
    |> mcp_post("tools/list", %{}, bearer: bearer, session_id: session_id, id: 2)
    |> json_response(200)
    |> get_in(["result", "tools"])
  end

  defp call_tool(conn, bearer, session_id, name, arguments, id \\ 3) do
    conn
    |> mcp_post("tools/call", %{"name" => name, "arguments" => arguments},
      bearer: bearer,
      session_id: session_id,
      id: id
    )
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp tool_text(result) do
    [%{"type" => "text", "text" => text}] = result["content"]
    text
  end

  defp with_harness(conn) do
    user = user_fixture!()
    harness = harness_fixture!(user)
    %{conn: conn, user: user, harness: harness, key: harness.__metadata__.plaintext_api_key}
  end

  describe "initialize and tools/list" do
    test "returns exactly DESIGN.md's tool names for a Harness key", %{conn: conn} do
      %{key: key} = with_harness(conn)

      {init_conn, session_id} = initialize(conn, key)
      assert init_conn.status == 200
      assert json_response(init_conn, 200)["result"]["protocolVersion"] == "2025-06-18"

      names = conn |> tools_list(key, session_id) |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == Enum.sort(@tool_names)
    end

    test "returns exactly the same tool names for an Agent key", %{conn: conn} do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      key = agent_key_fixture!(agent, owner).__metadata__.plaintext_api_key

      {_init_conn, session_id} = initialize(conn, key)
      names = conn |> tools_list(key, session_id) |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == Enum.sort(@tool_names)
    end
  end

  describe "authentication" do
    test "401 without a bearer token, before AshAi.Mcp.Router is reached", %{conn: conn} do
      conn =
        mcp_post(conn, "initialize", %{"protocolVersion" => "2025-06-18", "capabilities" => %{}})

      assert conn.status == 401
    end

    test "401 with a revoked Harness key", %{conn: conn} do
      %{user: user, harness: harness, key: key} = with_harness(conn)
      Artifacts.Accounts.revoke_harness!(harness, actor: user)

      conn =
        mcp_post(conn, "initialize", %{"protocolVersion" => "2025-06-18", "capabilities" => %{}},
          bearer: key
        )

      assert conn.status == 401
    end
  end

  test "a bare notification (no id) gets 202 with no body", %{conn: conn} do
    %{key: key} = with_harness(conn)

    conn =
      conn
      |> on_app_host()
      |> put_req_header("authorization", "Bearer #{key}")
      |> put_req_header("content-type", "application/json")
      |> post(@mcp_path, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert conn.status == 202
    assert conn.resp_body == ""
  end

  describe "tools/call" do
    test "publish_artifact creates when artifact_id is absent", %{conn: conn} do
      %{key: key} = with_harness(conn)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "publish_artifact", %{
          "input" => %{"title" => "Board", "html" => "<p>hi</p>"}
        })

      refute result["isError"]
      assert %{"current_version" => 1} = Jason.decode!(tool_text(result))
    end

    test "publish_artifact publishes a new Version when artifact_id is present", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "publish_artifact", %{
          "input" => %{"artifact_id" => artifact.id, "html" => "<p>2</p>"}
        })

      refute result["isError"]
      assert %{"current_version" => 2} = Jason.decode!(tool_text(result))
    end

    test "publish_artifact with a stale if_version is isError conflict", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "publish_artifact", %{
          "input" => %{"artifact_id" => artifact.id, "html" => "<p>stale</p>", "if_version" => 1}
        })

      assert result["isError"] == true
      assert tool_text(result) == "conflict"
    end

    test "change_state applies ops to an existing Artifact", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "change_state", %{
          "id" => artifact.id,
          "input" => %{"ops" => [%{"op" => "set", "path" => "a", "value" => 1}]}
        })

      refute result["isError"]
      assert {:ok, %{"a" => 1}} = Publishing.get_state(artifact.id, actor: user)
    end

    test "submit records a Submission", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "submit", %{
          "id" => artifact.id,
          "input" => %{"payload" => %{"note" => "done"}}
        })

      refute result["isError"]
    end

    test "wait returns immediately when since is behind an existing Submission", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {:ok, _first} = Publishing.submit(artifact, "one", actor: user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "wait", %{
          "input" => %{"artifact_id" => artifact.id, "since" => 0, "timeout" => 0}
        })

      refute result["isError"]
      assert [%{"payload" => "one"}] = Jason.decode!(tool_text(result))
    end

    test "wait blocks until a Submission made from another process arrives", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      waiter =
        Task.async(fn ->
          call_tool(conn, key, session_id, "wait", %{
            "input" => %{"artifact_id" => artifact.id, "since" => 0, "timeout" => 5_000}
          })
        end)

      Process.sleep(50)
      {:ok, submitted} = Publishing.submit(artifact, "later", actor: user)
      submission_id = submitted.__metadata__.submission_id

      result = Task.await(waiter)
      refute result["isError"]
      assert [%{"id" => ^submission_id, "payload" => "later"}] = Jason.decode!(tool_text(result))
    end

    test "history returns the request's Events", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "history", %{
          "input" => %{"artifact_id" => artifact.id}
        })

      refute result["isError"]
      assert [%{"kind" => "version_published"}] = Jason.decode!(tool_text(result))
    end

    test "get_artifact returns metadata", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "get_artifact", %{
          "input" => %{"artifact_id" => artifact.id}
        })

      refute result["isError"]
      assert %{"id" => id, "current_version" => 1} = Jason.decode!(tool_text(result))
      assert id == artifact.id
    end

    test "get_artifact for a non-member is isError not_found", %{conn: conn} do
      owner = user_fixture!()
      artifact = artifact_fixture!(owner)

      %{key: key} = with_harness(conn)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "get_artifact", %{
          "input" => %{"artifact_id" => artifact.id}
        })

      assert result["isError"] == true
      assert tool_text(result) == "not_found"
    end

    test "list_artifacts lists a member's open Artifacts (the 'list' tool)", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      organization = personal_organization!(user)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result =
        call_tool(conn, key, session_id, "list_artifacts", %{
          "input" => %{"organization_id" => organization.id}
        })

      refute result["isError"]
      assert [%{"id" => id}] = Jason.decode!(tool_text(result))
      assert id == artifact.id
    end

    test "rename_artifact, archive_artifact, and unarchive_artifact", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      artifact = artifact_fixture!(user)
      {_init_conn, session_id} = initialize(conn, key)

      rename_result =
        call_tool(conn, key, session_id, "rename_artifact", %{
          "id" => artifact.id,
          "input" => %{"title" => "Renamed"}
        })

      refute rename_result["isError"]
      assert %{"title" => "Renamed"} = Jason.decode!(tool_text(rename_result))

      archive_result =
        call_tool(conn, key, session_id, "archive_artifact", %{
          "id" => artifact.id,
          "input" => %{}
        })

      refute archive_result["isError"]
      refute Jason.decode!(tool_text(archive_result))["archived_at"] == nil

      unarchive_result =
        call_tool(conn, key, session_id, "unarchive_artifact", %{
          "id" => artifact.id,
          "input" => %{}
        })

      refute unarchive_result["isError"]
      assert Jason.decode!(tool_text(unarchive_result))["archived_at"] == nil
    end

    test "list_organizations", %{conn: conn} do
      %{user: user, key: key} = with_harness(conn)
      organization = personal_organization!(user)
      {_init_conn, session_id} = initialize(conn, key)

      result = call_tool(conn, key, session_id, "list_organizations", %{"input" => %{}})

      refute result["isError"]
      # Organization's `:read` (`defaults [:read]`) carries Ash's own
      # default keyset pagination, unlike Artifact's hand-written `:list`.
      assert %{"results" => [%{"id" => id} | _]} = Jason.decode!(tool_text(result))
      assert id == organization.id
    end
  end
end
