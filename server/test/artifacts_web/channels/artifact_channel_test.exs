defmodule ArtifactsWeb.ArtifactChannelTest do
  use ArtifactsWeb.ChannelCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias ArtifactsWeb.{ArtifactChannel, ArtifactSocket, PageToken}

  setup do
    user = user_fixture!()
    artifact = artifact_fixture!(user)

    {:ok, _} =
      Publishing.change_state(artifact, [%{"op" => "set", "path" => "a.b", "value" => 1}],
        actor: user
      )

    %{user: user, artifact: artifact}
  end

  defp join_as(artifact, user) do
    {:ok, socket} = connect(ArtifactSocket, %{"t" => PageToken.sign(artifact.id, user.id)})
    subscribe_and_join(socket, ArtifactChannel, "artifact:" <> artifact.id)
  end

  describe "socket connect" do
    test "a valid token connects and assigns the actor and the token's artifact id", %{
      user: user,
      artifact: artifact
    } do
      assert {:ok, socket} =
               connect(ArtifactSocket, %{"t" => PageToken.sign(artifact.id, user.id)})

      assert socket.assigns.actor.id == user.id
      assert socket.assigns.artifact_id == artifact.id
    end

    test "a missing, tampered, or expired token is refused" do
      assert :error = connect(ArtifactSocket, %{})
      assert :error = connect(ArtifactSocket, %{"t" => "not-a-real-token"})

      expired =
        Phoenix.Token.sign(ArtifactsWeb.Endpoint, "artifact page v1", %{
          artifact_id: "whatever",
          user_id: "whatever"
        })

      assert :error = connect(ArtifactSocket, %{"t" => expired})
    end
  end

  describe "join" do
    test "replies with the version and the flat leaves, then pushes presence", %{
      user: user,
      artifact: artifact
    } do
      assert {:ok, %{version: 1, state: %{"a.b" => 1}}, _socket} = join_as(artifact, user)

      user_id = user.id
      user_name = user.name
      assert_push "presence_state", %{^user_id => %{metas: [%{name: ^user_name, meta: %{}}]}}
    end

    test "a token minted for a different artifact is refused", %{user: user, artifact: artifact} do
      other = artifact_fixture!(user)
      {:ok, socket} = connect(ArtifactSocket, %{"t" => PageToken.sign(other.id, user.id)})

      assert {:error, %{error: "not_found"}} =
               subscribe_and_join(socket, ArtifactChannel, "artifact:" <> artifact.id)
    end

    test "an archived artifact refuses the join", %{user: user, artifact: artifact} do
      {:ok, _} = Publishing.archive(artifact, actor: user)
      assert {:error, %{error: "archived"}} = join_as(artifact, user)
    end
  end

  describe "state:ops" do
    test "persists, replies :ok, and reaches every subscriber including the writer", %{
      user: user,
      artifact: artifact
    } do
      {:ok, _reply, writer} = join_as(artifact, user)
      {:ok, _reply, _reader} = join_as(artifact, add_member!(user, artifact))

      ref =
        push(writer, "state:ops", %{"ops" => [%{"op" => "set", "path" => "a.c", "value" => "x"}]})

      assert_reply ref, :ok
      assert_push "state:ops", %{ops: [%{"op" => "set", "path" => "a.c", "value" => "x"}], by: by}
      assert by.type == "user"
      assert by.id == user.id

      assert {:ok, %{"a.b" => 1, "a.c" => "x"}} = Publishing.get_leaves(artifact.id, actor: user)
    end

    test "an invalid op replies with {error: invalid} and writes nothing", %{
      user: user,
      artifact: artifact
    } do
      {:ok, _reply, socket} = join_as(artifact, user)

      ref =
        push(socket, "state:ops", %{"ops" => [%{"op" => "set", "path" => "a..b", "value" => 1}]})

      assert_reply ref, :error, %{error: "invalid"}
    end
  end

  describe "presence:update" do
    test "succeeds immediately after join, before the :after_join presence_state push", %{
      user: user,
      artifact: artifact
    } do
      # :after_join is sent to this channel process before its join reply
      # ever leaves the process, so it is always handled before a push a
      # client only makes after receiving that reply — such as
      # runtime.js flushing any meta tracked while still offline.
      {:ok, _reply, socket} = join_as(artifact, user)
      ref = push(socket, "presence:update", %{"meta" => %{"cursor" => [0, 0]}})
      assert_reply ref, :ok
    end

    test "replaces this viewer's meta and is capped at 4 KiB", %{user: user, artifact: artifact} do
      {:ok, _reply, socket} = join_as(artifact, user)
      assert_push "presence_state", _state

      ref = push(socket, "presence:update", %{"meta" => %{"cursor" => [1, 2]}})
      assert_reply ref, :ok
      user_id = user.id

      assert_push "presence_diff", %{
        joins: %{^user_id => %{metas: [%{meta: %{"cursor" => [1, 2]}}]}}
      }

      oversized = %{"blob" => String.duplicate("x", 5000)}
      ref = push(socket, "presence:update", %{"meta" => oversized})
      assert_reply ref, :error, %{error: "invalid"}
    end
  end

  describe "broadcast" do
    test "reaches the other viewers, not the sender", %{user: user, artifact: artifact} do
      {:ok, _reply, sender} = join_as(artifact, user)
      {:ok, _reply, _other} = join_as(artifact, add_member!(user, artifact))

      push(sender, "broadcast", %{"topic" => "pointer", "data" => %{"x" => 1}})

      user_id = user.id

      assert_push "broadcast", %{
        topic: "pointer",
        data: %{"x" => 1},
        from: %{type: "user", id: ^user_id}
      }
    end
  end

  describe "submit" do
    test "records the actor, the state, and the payload, and pushes no submission event", %{
      user: user,
      artifact: artifact
    } do
      {:ok, _reply, socket} = join_as(artifact, user)

      ref = push(socket, "submit", %{"payload" => %{"choice" => "B"}})
      assert_reply ref, :ok, %{id: submission_id}
      refute_push "submission", _

      assert {:ok, submission} =
               Ash.get(Artifacts.Publishing.Submission, submission_id, actor: user)

      assert submission.state == %{"a" => %{"b" => 1}}
      assert submission.payload == %{"choice" => "B"}
    end
  end

  describe "publish" do
    test "is compare-and-set on the version, and pushes to every subscriber", %{
      user: user,
      artifact: artifact
    } do
      {:ok, _reply, socket} = join_as(artifact, user)

      ref = push(socket, "publish", %{"html" => "<p>2</p>", "if_version" => 1})
      assert_reply ref, :ok, %{version: 2}
      assert_push "version", %{version: 2, by: %{type: "user"}}

      stale = push(socket, "publish", %{"html" => "<p>late</p>", "if_version" => 1})
      assert_reply stale, :error, %{error: "conflict"}
    end
  end

  describe "archive" do
    test "an open page's writes fail after the artifact is archived", %{
      user: user,
      artifact: artifact
    } do
      {:ok, _reply, socket} = join_as(artifact, user)
      {:ok, _} = Publishing.archive(artifact, actor: user)

      ops = push(socket, "state:ops", %{"ops" => [%{"op" => "set", "path" => "z", "value" => 1}]})
      assert_reply ops, :error, %{error: "archived"}

      submit = push(socket, "submit", %{"payload" => nil})
      assert_reply submit, :error, %{error: "archived"}

      publish = push(socket, "publish", %{"html" => "<p>2</p>", "if_version" => 1})
      assert_reply publish, :error, %{error: "archived"}
    end
  end

  # A second User who can also open the artifact: added to its Organization
  # by the owning `user`, who is already a member (DOMAIN.md §3.1: any
  # member adds another by email).
  defp add_member!(owner, artifact) do
    other = user_fixture!()

    {:ok, _membership} =
      Artifacts.Accounts.add_member(artifact.organization_id, other.email, actor: owner)

    other
  end
end
