defmodule Artifacts.PublishingTest do
  use Artifacts.DataCase, async: false

  require Ash.Query

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias Artifacts.Publishing.{Errors, Event, StateEntry, Submission, Version}

  setup do
    user = user_fixture!()
    organization = personal_organization!(user)
    %{user: user, organization: organization}
  end

  describe "create and versions" do
    test "creates version 1 with an unguessable id and broadcasts it", %{user: user} do
      Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:pending")

      {:ok, artifact} = Publishing.create_artifact("Board", html(), actor: user)
      Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:#{artifact.id}")

      assert String.length(artifact.id) == 22
      assert artifact.current_version == 1

      assert {:ok, version} = Ash.get(Version, [artifact_id: artifact.id, number: 1], actor: user)
      assert version.html == html()

      {:ok, artifact2} = Publishing.publish(artifact, "<p>v2</p>", nil, actor: user)
      assert_receive {:version, %{version: 2, by: %{type: "user", id: user_id}}}
      assert user_id == user.id
      assert artifact2.current_version == 2
    end

    test "rejects an empty title, non-string html, and oversized or invalid html", %{user: user} do
      assert {:error, error} = Publishing.create_artifact("", html(), actor: user)
      assert Errors.to_code(error) == "invalid"

      assert {:error, error} = Publishing.create_artifact("x", <<0xFF, 0xFE>>, actor: user)
      assert Errors.to_code(error) == "invalid"

      oversized = String.duplicate("a", 16 * 1024 * 1024 + 1)
      assert {:error, error} = Publishing.create_artifact("x", oversized, actor: user)
      assert Errors.to_code(error) == "invalid"
    end
  end

  describe "publish and if_version" do
    test "publish with if_version refuses a stale writer", %{user: user} do
      artifact = artifact_fixture!(user)

      assert {:ok, artifact2} = Publishing.publish(artifact, "<p>2</p>", 1, actor: user)
      assert artifact2.current_version == 2

      assert {:error, error} = Publishing.publish(artifact2, "<p>late</p>", 1, actor: user)
      assert Errors.to_code(error) == "conflict"

      assert {:ok, current} = Ash.get(Version, [artifact_id: artifact.id, number: 2], actor: user)
      assert current.html == "<p>2</p>"
    end

    test "two concurrent publishes with the same if_version: exactly one succeeds", %{user: user} do
      artifact = artifact_fixture!(user)

      results =
        [
          Task.async(fn -> Publishing.publish(artifact, "<p>a</p>", 1, actor: user) end),
          Task.async(fn -> Publishing.publish(artifact, "<p>b</p>", 1, actor: user) end)
        ]
        |> Task.await_many()

      successes = Enum.filter(results, &match?({:ok, _}, &1))
      failures = Enum.filter(results, &match?({:error, _}, &1))

      assert length(successes) == 1
      assert length(failures) == 1
      assert {:error, error} = hd(failures)
      assert Errors.to_code(error) == "conflict"

      assert {:ok, refreshed} = Ash.get(Artifacts.Publishing.Artifact, artifact.id, actor: user)
      assert refreshed.current_version == 2
    end
  end

  describe "list" do
    test "orders open Artifacts by most recently updated, filters archived", %{
      user: user,
      organization: organization
    } do
      first = artifact_fixture!(user, title: "first")
      second = artifact_fixture!(user, title: "second")
      {:ok, _} = Publishing.publish(first, "<p>again</p>", nil, actor: user)

      assert {:ok, open} = Publishing.list_artifacts(organization.id, actor: user)
      assert Enum.map(open, & &1.id) == [first.id, second.id]

      {:ok, _} = Publishing.archive(second, actor: user)

      assert {:ok, open} = Publishing.list_artifacts(organization.id, actor: user)
      assert Enum.map(open, & &1.id) == [first.id]

      assert {:ok, archived} =
               Publishing.list_artifacts(organization.id, %{archived: true}, actor: user)

      assert Enum.map(archived, & &1.id) == [second.id]
    end
  end

  describe "archive" do
    test "hides the Artifact, refuses content changes, and keeps every row", %{user: user} do
      artifact = artifact_fixture!(user)

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "a", "value" => 1}],
          actor: user
        )

      {:ok, submitted} = Publishing.submit(artifact, nil, actor: user)
      submission_id = submitted.__metadata__.submission_id

      assert {:ok, archived} = Publishing.archive(artifact, actor: user)
      assert %DateTime{} = archived.archived_at

      # Archiving an archived Artifact changes nothing.
      assert {:ok, archived_again} = Publishing.archive(archived, actor: user)
      assert archived_again.archived_at == archived.archived_at

      for {call, args} <- [
            {&Publishing.publish/4, ["<p>2</p>", nil]},
            {&Publishing.change_state/3, [[%{"op" => "set", "path" => "b", "value" => 2}]]},
            {&Publishing.submit/3, [nil]}
          ] do
        assert {:error, error} = apply(call, [archived | args] ++ [[actor: user]])
        assert Errors.to_code(error) == "archived"
      end

      # Still readable: State, Submissions, and the Version stay intact.
      assert {:ok, state} = Publishing.get_state(artifact.id, actor: user)
      assert state == %{"a" => 1}

      assert {:ok, submission} = Ash.get(Submission, submission_id, actor: user)
      assert submission.id == submission_id

      assert {:ok, refreshed} = Ash.get(Artifacts.Publishing.Artifact, artifact.id, actor: user)
      assert refreshed.current_version == 1
    end

    test "unarchive returns an Artifact to Open", %{user: user} do
      artifact = artifact_fixture!(user)
      {:ok, archived} = Publishing.archive(artifact, actor: user)
      assert {:ok, reopened} = Publishing.unarchive(archived, actor: user)
      assert reopened.archived_at == nil
      assert {:ok, _} = Publishing.publish(reopened, "<p>ok</p>", nil, actor: user)
    end

    test "a content action refuses an Artifact archived through a different, stale handle", %{
      user: user
    } do
      artifact = artifact_fixture!(user)
      {:ok, _archived} = Publishing.archive(artifact, actor: user)

      # `artifact` was never reassigned: it still says archived_at: nil, as a
      # long-lived caller (a channel process holding it across messages)
      # would. Every content action must refuse against the real row anyway.
      for {call, args} <- [
            {&Publishing.publish/4, ["<p>2</p>", nil]},
            {&Publishing.change_state/3, [[%{"op" => "set", "path" => "b", "value" => 2}]]},
            {&Publishing.submit/3, [nil]}
          ] do
        assert {:error, error} = apply(call, [artifact | args] ++ [[actor: user]])
        assert Errors.to_code(error) == "archived"
      end
    end
  end

  describe "rename" do
    test "renames without writing an Event", %{user: user} do
      artifact = artifact_fixture!(user, title: "Old")
      before_count = event_count(artifact.id)

      assert {:ok, renamed} = Publishing.rename(artifact, "New", actor: user)
      assert renamed.title == "New"
      assert event_count(artifact.id) == before_count
    end
  end

  describe "history" do
    test "records every write in order, joined with what it describes", %{user: user} do
      artifact = artifact_fixture!(user)

      {:ok, _} =
        Publishing.change_state(
          artifact,
          [
            %{"op" => "set", "path" => "a.b", "value" => 1},
            %{"op" => "set", "path" => "gone", "value" => nil}
          ],
          actor: user
        )

      {:ok, submitted} = Publishing.submit(artifact, %{"ok" => true}, actor: user)
      submission_id = submitted.__metadata__.submission_id
      {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)
      {:ok, _} = Publishing.archive(artifact, actor: user)

      assert {:ok, events} = Publishing.history(artifact.id, actor: user)

      assert Enum.map(events, & &1.kind) == [
               :version_published,
               :state_changed,
               :submission_made,
               :version_published
             ]

      [published1, state_changed, submission_made, published2] = events

      assert published1.data == %{number: 1}
      assert published1.actor.type == "user"

      assert state_changed.data == %{
               ops: [
                 %{"op" => "set", "path" => "a.b", "value" => 1},
                 %{"op" => "delete", "path" => "gone"}
               ]
             }

      assert submission_made.data.submission_id == submission_id
      assert submission_made.data.version == 1
      assert submission_made.data.state == %{"a" => %{"b" => 1}}
      assert submission_made.data.payload == %{"ok" => true}

      assert published2.data == %{number: 2}

      first_id = hd(events).id

      assert {:ok, [%{kind: :state_changed} | _]} =
               Publishing.history(artifact.id, %{after: first_id}, actor: user)

      assert {:ok, []} =
               Publishing.history(artifact.id, %{after: List.last(events).id}, actor: user)
    end

    test "include_html carries the Version's HTML only when asked", %{user: user} do
      artifact = artifact_fixture!(user)

      assert {:ok, [without_html]} = Publishing.history(artifact.id, actor: user)
      refute Map.has_key?(without_html.data, :html)

      assert {:ok, [with_html]} =
               Publishing.history(artifact.id, %{include_html: true}, actor: user)

      assert with_html.data.html == html()
    end
  end

  describe "state" do
    test "persists leaves of every JSON shape and broadcasts the ops", %{user: user} do
      artifact = artifact_fixture!(user)
      Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:#{artifact.id}")

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

      assert {:ok, _} = Publishing.change_state(artifact, ops, actor: user)

      assert_receive {:state_ops, %{ops: broadcast_ops}}
      assert %{"op" => "delete", "path" => "nothing"} in broadcast_ops

      assert {:ok, state} = Publishing.get_state(artifact.id, actor: user)

      assert state == %{
               "cards" => %{"c1" => %{"title" => "Fix nav", "column" => "now"}},
               "count" => 3,
               "tags" => ["a", "b"],
               "empty" => %{}
             }
    end

    test "set replaces subtrees and ancestors exactly like the in-memory rules", %{user: user} do
      artifact = artifact_fixture!(user)

      {:ok, _} =
        Publishing.change_state(
          artifact,
          [
            %{"op" => "set", "path" => "a.b", "value" => 1},
            %{"op" => "set", "path" => "a.c.d", "value" => 2}
          ],
          actor: user
        )

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "a.c", "value" => 9}],
          actor: user
        )

      assert leaves(artifact.id) == %{"a.b" => 1, "a.c" => 9}

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "a", "value" => "flat"}],
          actor: user
        )

      assert leaves(artifact.id) == %{"a" => "flat"}

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "a.x", "value" => true}],
          actor: user
        )

      assert leaves(artifact.id) == %{"a.x" => true}

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "delete", "path" => "a"}], actor: user)

      assert leaves(artifact.id) == %{}
    end

    test "invalid ops are rejected without writes", %{user: user} do
      artifact = artifact_fixture!(user)

      assert {:error, error} =
               Publishing.change_state(
                 artifact,
                 [%{"op" => "set", "path" => "a..b", "value" => 1}],
                 actor: user
               )

      assert Errors.to_code(error) == "invalid"
      assert leaves(artifact.id) == %{}
    end

    test "an empty ops batch is rejected as invalid", %{user: user} do
      artifact = artifact_fixture!(user)
      assert {:error, error} = Publishing.change_state(artifact, [], actor: user)
      assert Errors.to_code(error) == "invalid"
    end

    test "exactly one Event is written per change_state call, regardless of op count", %{
      user: user
    } do
      artifact = artifact_fixture!(user)
      before_count = event_count(artifact.id)

      ops = for i <- 1..5, do: %{"op" => "set", "path" => "k#{i}", "value" => i}
      {:ok, _} = Publishing.change_state(artifact, ops, actor: user)

      assert event_count(artifact.id) == before_count + 1
    end

    test "the 10,000-row cap rolls back the whole batch and sends no broadcast", %{user: user} do
      artifact = artifact_fixture!(user)
      Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:#{artifact.id}")

      fill_ops = for i <- 1..10_000, do: %{"op" => "set", "path" => "row#{i}", "value" => i}
      assert {:ok, _} = Publishing.change_state(artifact, fill_ops, actor: user)
      assert_receive {:state_ops, _}

      assert {:error, error} =
               Publishing.change_state(
                 artifact,
                 [%{"op" => "set", "path" => "overflow", "value" => 1}],
                 actor: user
               )

      assert Errors.to_code(error) == "quota"
      refute_receive {:state_ops, _}, 200

      assert Ash.count!(Ash.Query.filter(StateEntry, artifact_id == ^artifact.id),
               authorize?: false
             ) == 10_000

      refute Ash.exists?(
               Ash.Query.filter(StateEntry, artifact_id == ^artifact.id and path == "overflow"),
               authorize?: false
             )
    end
  end

  describe "submissions and wait" do
    test "submit snapshots state and version, and wait returns it", %{user: user} do
      artifact = artifact_fixture!(user)

      {:ok, artifact} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "choice", "value" => "B"}],
          actor: user
        )

      {:ok, artifact} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)

      waiter =
        Task.async(fn ->
          Publishing.wait(artifact.id, %{since: 0, timeout: 5_000}, actor: user)
        end)

      assert {:ok, submitted} = Publishing.submit(artifact, %{"notes" => "ship it"}, actor: user)
      submission_id = submitted.__metadata__.submission_id

      assert {:ok, [submission]} = Task.await(waiter)
      assert submission.id == submission_id
      assert submission.version == 2
      assert submission.state == %{"choice" => "B"}
      assert submission.payload == %{"notes" => "ship it"}

      assert {:ok, []} =
               Publishing.wait(artifact.id, %{since: submission_id, timeout: 0}, actor: user)
    end

    test "submit records the Artifact's true current Version, not a stale caller handle", %{
      user: user
    } do
      artifact = artifact_fixture!(user)
      # `artifact` is never reassigned, so it still says current_version: 1 —
      # a long-lived caller (a channel process) would see the same thing.
      {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)

      assert {:ok, submitted} = Publishing.submit(artifact, nil, actor: user)
      submission_id = submitted.__metadata__.submission_id

      submission = Ash.get!(Submission, submission_id, authorize?: false)
      assert submission.version == 2
    end

    test "wait returns immediately when a newer submission already exists", %{user: user} do
      artifact = artifact_fixture!(user)
      {:ok, first} = Publishing.submit(artifact, "one", actor: user)
      {:ok, second} = Publishing.submit(artifact, "two", actor: user)

      assert {:ok, [submission]} =
               Publishing.wait(
                 artifact.id,
                 %{since: first.__metadata__.submission_id, timeout: 0},
                 actor: user
               )

      assert submission.id == second.__metadata__.submission_id
    end

    test "wait with since omitted starts after the latest submission now", %{user: user} do
      artifact = artifact_fixture!(user)
      {:ok, _first} = Publishing.submit(artifact, "one", actor: user)

      waiter = Task.async(fn -> Publishing.wait(artifact.id, %{timeout: 5_000}, actor: user) end)
      Process.sleep(50)
      {:ok, second} = Publishing.submit(artifact, "two", actor: user)

      assert {:ok, [submission]} = Task.await(waiter)
      assert submission.id == second.__metadata__.submission_id
    end

    test "wait with a zero timeout is one query and times out empty", %{user: user} do
      artifact = artifact_fixture!(user)
      assert {:ok, []} = Publishing.wait(artifact.id, %{since: 0, timeout: 0}, actor: user)
    end

    test "the 10,000-submission cap refuses further submits", %{user: user} do
      artifact = artifact_fixture!(user)

      Enum.each(1..10_000, fn _ ->
        Ash.create!(
          Submission,
          %{artifact_id: artifact.id, version: 1, state: %{}, user_id: user.id},
          authorize?: false
        )
      end)

      assert {:error, error} = Publishing.submit(artifact, nil, actor: user)
      assert Errors.to_code(error) == "quota"
    end
  end

  defp leaves(artifact_id) do
    StateEntry
    |> Ash.Query.filter(artifact_id == ^artifact_id)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.path, &1.value})
  end

  defp event_count(artifact_id) do
    Ash.count!(Ash.Query.filter(Event, artifact_id == ^artifact_id), authorize?: false)
  end
end
