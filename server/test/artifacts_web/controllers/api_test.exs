defmodule ArtifactsWeb.APITest do
  use ArtifactsWeb.ConnCase, async: false

  alias Artifacts.Store

  @html "<!doctype html><p>hi</p>"

  defp create(conn, attrs \\ %{}) do
    conn
    |> post(~p"/api/artifacts", Map.merge(%{"title" => "Board", "html" => @html}, attrs))
    |> json_response(201)
  end

  test "create, show, list, delete", %{conn: conn} do
    created = create(conn)
    assert %{"id" => id, "title" => "Board", "version" => 1, "url" => url} = created
    assert url == url(~p"/a/#{id}")

    assert json_response(get(conn, ~p"/api/artifacts/#{id}"), 200) == created
    assert [%{"id" => ^id}] = json_response(get(conn, ~p"/api/artifacts"), 200)

    assert response(delete(conn, ~p"/api/artifacts/#{id}"), 204)
    assert json_response(get(conn, ~p"/api/artifacts/#{id}"), 404) == %{"error" => "not_found"}
    assert json_response(delete(conn, ~p"/api/artifacts/#{id}"), 404) == %{"error" => "not_found"}
  end

  test "create validates its input", %{conn: conn} do
    assert %{"error" => "title and html are required"} =
             json_response(post(conn, ~p"/api/artifacts", %{"title" => "x"}), 422)

    assert %{"error" => "title must be a non-empty string"} =
             json_response(post(conn, ~p"/api/artifacts", %{"title" => "", "html" => @html}), 422)
  end

  test "publish versions with optional title and if_version", %{conn: conn} do
    %{"id" => id} = create(conn)

    assert %{"version" => 2} =
             json_response(
               put(conn, ~p"/api/artifacts/#{id}", %{"html" => "<p>2</p>", "title" => "Board 2"}),
               200
             )

    assert %{"error" => "conflict"} =
             json_response(
               put(conn, ~p"/api/artifacts/#{id}", %{"html" => "<p>x</p>", "if_version" => 1}),
               409
             )

    assert %{"error" => "html is required"} =
             json_response(put(conn, ~p"/api/artifacts/#{id}", %{}), 422)

    assert json_response(put(conn, ~p"/api/artifacts/missing", %{"html" => "<p></p>"}), 404)

    assert [%{"number" => 1}, %{"number" => 2, "published_by" => "agent"}] =
             json_response(get(conn, ~p"/api/artifacts/#{id}/versions"), 200)

    assert %{"number" => 2, "html" => "<p>2</p>"} =
             json_response(get(conn, ~p"/api/artifacts/#{id}/versions/current"), 200)

    assert %{"number" => 1, "html" => @html} =
             json_response(get(conn, ~p"/api/artifacts/#{id}/versions/1"), 200)

    assert json_response(get(conn, ~p"/api/artifacts/#{id}/versions/9"), 404)
    assert json_response(get(conn, ~p"/api/artifacts/#{id}/versions/nope"), 404)
  end

  test "state reads and writes as the agent", %{conn: conn} do
    %{"id" => id} = create(conn)

    ops = [%{"op" => "set", "path" => "cards.c1", "value" => %{"column" => "now"}}]

    assert %{
             "applied" => [
               %{"op" => "set", "path" => "cards.c1", "value" => %{"column" => "now"}}
             ]
           } =
             json_response(post(conn, ~p"/api/artifacts/#{id}/state", %{"ops" => ops}), 200)

    assert Store.leaves(id) == %{"cards.c1.column" => "now"}

    assert json_response(get(conn, ~p"/api/artifacts/#{id}/state"), 200) == %{
             "cards" => %{"c1" => %{"column" => "now"}}
           }

    assert json_response(get(conn, ~p"/api/artifacts/#{id}/state?path=cards.c1.column"), 200) ==
             "now"

    assert json_response(get(conn, ~p"/api/artifacts/#{id}/state?path=nope"), 200) == nil

    assert %{"error" => "ops is required"} =
             json_response(post(conn, ~p"/api/artifacts/#{id}/state", %{}), 422)

    assert %{"error" => "ops must be a list"} =
             json_response(post(conn, ~p"/api/artifacts/#{id}/state", %{"ops" => %{}}), 422)

    assert json_response(get(conn, ~p"/api/artifacts/missing/state"), 404)
  end

  test "submissions: create, list since a cursor, and long-poll", %{conn: conn} do
    %{"id" => id} = create(conn)

    assert response(get(conn, ~p"/api/artifacts/#{id}/submissions?timeout=0"), 204)

    assert %{
             "id" => first,
             "payload" => "one",
             "viewer_id" => nil,
             "version" => 1,
             "state" => %{}
           } =
             json_response(
               post(conn, ~p"/api/artifacts/#{id}/submissions", %{"payload" => "one"}),
               201
             )

    assert %{"id" => second} =
             json_response(
               post(conn, ~p"/api/artifacts/#{id}/submissions", %{
                 "payload" => %{"k" => 2},
                 "viewer_id" => "v9"
               }),
               201
             )

    assert [%{"id" => ^first}, %{"id" => ^second, "viewer_id" => "v9"}] =
             json_response(get(conn, ~p"/api/artifacts/#{id}/submissions"), 200)

    assert [%{"id" => ^second}] =
             json_response(get(conn, ~p"/api/artifacts/#{id}/submissions?since=#{first}"), 200)

    assert [%{"id" => ^second}] =
             json_response(
               get(conn, ~p"/api/artifacts/#{id}/submissions?since=#{first}&timeout=5"),
               200
             )

    assert response(
             get(conn, ~p"/api/artifacts/#{id}/submissions?since=#{second}&timeout=0"),
             204
           )

    assert json_response(get(conn, ~p"/api/artifacts/missing/submissions"), 404)
  end

  @doc false
  def wait_then_submit(conn, id) do
    # The request blocks until the submission below lands; the timeout is a failure bound.
    task = Task.async(fn -> get(conn, ~p"/api/artifacts/#{id}/submissions?timeout=5") end)
    {:ok, submission} = Store.submit(id, "later", nil)
    {Task.await(task), submission}
  end

  test "long-poll returns the submission that arrives while waiting", %{conn: conn} do
    %{"id" => id} = create(conn)
    {response, submission} = wait_then_submit(conn, id)

    assert [%{"id" => id_seen, "payload" => "later"}] = json_response(response, 200)
    assert id_seen == submission.id
  end
end
