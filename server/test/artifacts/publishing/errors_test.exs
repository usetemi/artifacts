defmodule Artifacts.Publishing.ErrorsTest do
  use Artifacts.DataCase, async: true

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias Artifacts.Publishing.Errors
  alias Artifacts.Publishing.Errors.{Archived, Conflict, Quota}

  test "conflict" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)
    assert {:error, error} = Publishing.publish(artifact, "<p>stale</p>", 1, actor: user)
    assert Errors.to_code(error) == "conflict"
  end

  test "archived" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    {:ok, archived} = Publishing.archive(artifact, actor: user)
    assert {:error, error} = Publishing.publish(archived, "<p>x</p>", nil, actor: user)
    assert Errors.to_code(error) == "archived"
  end

  test "not_found" do
    user = user_fixture!()
    assert {:error, error} = Ash.get(Publishing.Artifact, "does-not-exist", actor: user)
    assert Errors.to_code(error) == "not_found"
  end

  test "forbidden" do
    owner = user_fixture!()
    stranger = user_fixture!()
    artifact = artifact_fixture!(owner)
    assert {:error, error} = Publishing.publish(artifact, "<p>x</p>", nil, actor: stranger)
    assert Errors.to_code(error) == "forbidden"
  end

  test "quota" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)

    Enum.each(1..10_000, fn _ ->
      Ash.create!(
        Publishing.Submission,
        %{artifact_id: artifact.id, version: 1, state: %{}, user_id: user.id},
        authorize?: false
      )
    end)

    assert {:error, error} = Publishing.submit(artifact, nil, actor: user)
    assert Errors.to_code(error) == "quota"
  end

  test "invalid" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)
    assert {:error, error} = Publishing.change_state(artifact, [], actor: user)
    assert Errors.to_code(error) == "invalid"
  end

  test "unknown falls back for an unrecognized error shape" do
    assert Errors.to_code(%RuntimeError{message: "boom"}) == "unknown"
    assert Errors.to_code(nil) == "unknown"
  end

  test "the bare wrapped error resolves the same as the wrapping class" do
    assert Errors.to_code(Conflict.exception(artifact_id: "a")) == "conflict"
    assert Errors.to_code(Archived.exception(artifact_id: "a")) == "archived"
    assert Errors.to_code(Quota.exception(artifact_id: "a", limit: 10)) == "quota"
  end
end
