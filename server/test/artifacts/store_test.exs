defmodule Artifacts.StoreTest do
  use Artifacts.DataCase, async: false

  alias Artifacts.Store

  @html "<!doctype html><html><body><h1>Hi</h1></body></html>"

  defp create!(attrs \\ %{}) do
    {:ok, artifact} = Store.create(Map.merge(%{title: "Board", html: @html}, attrs))
    artifact
  end

  describe "create and versions" do
    test "creates version 1 with an unguessable id and broadcasts it" do
      artifact = create!()
      Phoenix.PubSub.subscribe(Artifacts.PubSub, Store.topic(artifact.id))

      assert String.length(artifact.id) == 22
      assert artifact.current_version == 1

      assert {:ok, %{html: @html, number: 1, published_by: "agent"}} =
               Store.current_version(artifact.id)

      assert [%{number: 1}] = Store.versions(artifact.id)

      {:ok, 2} = Store.publish(artifact.id, "<!doctype html><p>v2</p>", title: "Board v2")
      assert_receive {:version, 2, "agent"}
      assert {:ok, %{title: "Board v2", current_version: 2}} = Store.get(artifact.id)
    end

    test "rejects empty titles and oversized or invalid html" do
      assert {:error, "title must be a non-empty string"} =
               Store.create(%{title: "", html: @html})

      assert {:error, "html is not valid UTF-8"} =
               Store.create(%{title: "x", html: <<0xFF, 0xFE>>})

      assert {:error, "html larger than 16 MiB"} =
               Store.create(%{title: "x", html: String.duplicate("a", 16 * 1024 * 1024 + 1)})
    end

    test "publish with if_version refuses a stale writer" do
      artifact = create!()

      assert {:ok, 2} = Store.publish(artifact.id, "<p>2</p>", if_version: 1, by: "viewer:v1")

      assert {:error, :conflict} =
               Store.publish(artifact.id, "<p>late</p>", if_version: 1, by: "viewer:v2")

      assert {:ok, %{number: 2, published_by: "viewer:v1"}} = Store.current_version(artifact.id)
      assert {:error, :not_found} = Store.publish("missing", "<p></p>")
    end

    test "list orders by most recently updated" do
      first = create!(%{title: "first"})
      second = create!(%{title: "second"})
      {:ok, _} = Store.publish(first.id, "<p>again</p>")

      assert Enum.map(Store.list(), & &1.id) == [first.id, second.id]
    end

    test "delete cascades and reports missing ids" do
      artifact = create!()

      {:ok, _} =
        Store.apply_ops(artifact.id, [%{"op" => "set", "path" => "a", "value" => 1}], "agent")

      {:ok, _} = Store.submit(artifact.id, nil, nil)

      assert :ok = Store.delete(artifact.id)
      assert {:error, :not_found} = Store.get(artifact.id)
      assert Store.leaves(artifact.id) == %{}
      assert Store.submissions(artifact.id) == []
      assert {:error, :not_found} = Store.delete(artifact.id)
    end
  end

  describe "state" do
    test "persists leaves of every JSON shape and broadcasts the ops" do
      artifact = create!()
      Phoenix.PubSub.subscribe(Artifacts.PubSub, Store.topic(artifact.id))

      ops = [
        %{
          "op" => "set",
          "path" => "cards.c1",
          "value" => %{"title" => "Fix nav", "column" => "now"}
        },
        %{"op" => "set", "path" => "count", "value" => 3},
        %{"op" => "set", "path" => "tags", "value" => ["a", "b"]},
        %{"op" => "set", "path" => "nothing", "value" => nil},
        %{"op" => "set", "path" => "empty", "value" => %{}}
      ]

      assert {:ok, normalized} = Store.apply_ops(artifact.id, ops, "viewer:v1")
      assert %{op: :delete, path: "nothing"} in normalized
      assert_receive {:state_ops, ^normalized, "viewer:v1"}

      assert Store.leaves(artifact.id) == %{
               "cards.c1.title" => "Fix nav",
               "cards.c1.column" => "now",
               "count" => 3,
               "tags" => ["a", "b"],
               "empty" => %{}
             }

      assert Store.state(artifact.id)["cards"] == %{
               "c1" => %{"title" => "Fix nav", "column" => "now"}
             }
    end

    test "set replaces subtrees and ancestors exactly like the in-memory rules" do
      artifact = create!()

      {:ok, _} =
        Store.apply_ops(
          artifact.id,
          [
            %{"op" => "set", "path" => "a.b", "value" => 1},
            %{"op" => "set", "path" => "a.c.d", "value" => 2}
          ],
          "agent"
        )

      {:ok, _} =
        Store.apply_ops(artifact.id, [%{"op" => "set", "path" => "a.c", "value" => 9}], "agent")

      assert Store.leaves(artifact.id) == %{"a.b" => 1, "a.c" => 9}

      {:ok, _} =
        Store.apply_ops(
          artifact.id,
          [%{"op" => "set", "path" => "a", "value" => "flat"}],
          "agent"
        )

      assert Store.leaves(artifact.id) == %{"a" => "flat"}

      {:ok, _} =
        Store.apply_ops(
          artifact.id,
          [%{"op" => "set", "path" => "a.x", "value" => true}],
          "agent"
        )

      assert Store.leaves(artifact.id) == %{"a.x" => true}

      {:ok, _} = Store.apply_ops(artifact.id, [%{"op" => "delete", "path" => "a"}], "agent")
      assert Store.leaves(artifact.id) == %{}
    end

    test "invalid ops and missing artifacts are rejected without writes" do
      artifact = create!()

      assert {:error, "path has an empty segment"} =
               Store.apply_ops(
                 artifact.id,
                 [%{"op" => "set", "path" => "a..b", "value" => 1}],
                 "agent"
               )

      assert {:error, :not_found} =
               Store.apply_ops(
                 "missing",
                 [%{"op" => "set", "path" => "a", "value" => 1}],
                 "agent"
               )

      assert Store.leaves(artifact.id) == %{}
    end
  end

  describe "submissions" do
    test "submit snapshots state and version, and wait returns it" do
      artifact = create!()

      {:ok, _} =
        Store.apply_ops(
          artifact.id,
          [%{"op" => "set", "path" => "choice", "value" => "B"}],
          "viewer:v1"
        )

      {:ok, 2} = Store.publish(artifact.id, "<p>2</p>")

      # No synchronization needed: wait queries before it blocks, so it
      # finds the submission whether it lands before or after the subscribe.
      # The timeout is a failure bound, never waited on when the test passes.
      waiter = Task.async(fn -> Store.wait_for_submissions(artifact.id, 0, 5_000) end)

      assert {:ok, submission} = Store.submit(artifact.id, %{"notes" => "ship it"}, "v1")
      assert submission.version == 2
      assert submission.viewer_id == "v1"
      assert submission.state == %{"choice" => "B"}
      assert submission.payload == %{"notes" => "ship it"}

      assert {:ok, [%{id: id}]} = Task.await(waiter)
      assert id == submission.id
      assert Store.last_submission_id(artifact.id) == id
      assert Store.submissions(artifact.id, id) == []
    end

    test "wait returns immediately when a newer submission already exists" do
      artifact = create!()
      {:ok, first} = Store.submit(artifact.id, "one", nil)
      {:ok, second} = Store.submit(artifact.id, "two", nil)

      assert {:ok, [%{id: id}]} = Store.wait_for_submissions(artifact.id, first.id, 0)
      assert id == second.id
    end

    test "wait with a zero timeout is one query" do
      artifact = create!()
      assert :timeout = Store.wait_for_submissions(artifact.id, 0, 0)
    end

    test "submit on a missing artifact is not_found" do
      assert {:error, :not_found} = Store.submit("missing", nil, nil)
    end
  end
end
