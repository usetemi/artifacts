defmodule Artifacts.Publishing.ChannelNotifierTest do
  use Artifacts.DataCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias Artifacts.Publishing.{Artifact, ChannelNotifier}

  setup do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:#{artifact.id}")
    %{user: user, artifact: artifact}
  end

  test "notify/1 broadcasts :version for a publish notification with current_version 1", %{
    user: user
  } do
    # `create` has no notify/1 clause of its own (see the moduledoc): its
    # nested `publish` call is what actually broadcasts version 1. The
    # generated id makes it impossible to subscribe before a real
    # `create_artifact` call broadcasts, so this drives the notifier
    # directly with the same notification shape a version-1 publish
    # produces, covering the case the other `notify/1` tests below (which
    # all publish version 2+) don't reach.
    notification = %Ash.Notifier.Notification{
      resource: Artifact,
      action: %{name: :publish},
      data: %Artifact{id: "synthetic-artifact-id", current_version: 1},
      actor: user
    }

    Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:synthetic-artifact-id")

    ChannelNotifier.notify(notification)

    assert_receive {:version, %{version: 1, by: %{type: "user", id: user_id}}}
    assert user_id == user.id
  end

  test "publish broadcasts :version after commit", %{user: user, artifact: artifact} do
    assert {:ok, artifact2} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)
    assert_receive {:version, %{version: 2, by: by}}
    assert by == %{type: "user", id: user.id, name: user.name, harness: nil}
    assert artifact2.current_version == 2
  end

  test "change_state broadcasts :state_ops after commit", %{user: user, artifact: artifact} do
    ops = [%{"op" => "set", "path" => "a", "value" => 1}]
    assert {:ok, _} = Publishing.change_state(artifact, ops, actor: user)
    assert_receive {:state_ops, %{ops: ^ops, by: %{type: "user", id: user_id}}}
    assert user_id == user.id
  end

  test "submit broadcasts :submission after commit", %{user: user, artifact: artifact} do
    assert {:ok, submitted} = Publishing.submit(artifact, %{"note" => "hi"}, actor: user)
    submission_id = submitted.__metadata__.submission_id
    assert_receive {:submission, %{id: ^submission_id, by: %{type: "user"}}}
  end

  test "rename, archive, and unarchive send no broadcast", %{user: user, artifact: artifact} do
    {:ok, _} = Publishing.rename(artifact, "New Title", actor: user)
    refute_receive _, 100

    {:ok, archived} = Publishing.archive(artifact, actor: user)
    refute_receive _, 100

    {:ok, _} = Publishing.unarchive(archived, actor: user)
    refute_receive _, 100
  end

  test "no broadcast fires when ops are rejected before any transaction opens", %{
    user: user,
    artifact: artifact
  } do
    assert {:error, _error} =
             Publishing.change_state(artifact, [%{"op" => "set", "path" => "a..b", "value" => 1}],
               actor: user
             )

    refute_receive _, 200
  end
end
