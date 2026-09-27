defmodule Artifacts.Publishing.ChannelNotifierTest do
  use Artifacts.DataCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing

  setup do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    Phoenix.PubSub.subscribe(Artifacts.PubSub, "artifact:#{artifact.id}")
    %{user: user, artifact: artifact}
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

  test "no broadcast fires when the transaction rolls back", %{user: user, artifact: artifact} do
    assert {:error, _error} =
             Publishing.change_state(artifact, [%{"op" => "set", "path" => "a..b", "value" => 1}],
               actor: user
             )

    refute_receive _, 200
  end
end
