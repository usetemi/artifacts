defmodule Artifacts.Publishing.PolicyTest do
  use Artifacts.DataCase, async: true

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Accounts
  alias Artifacts.Publishing
  alias Artifacts.Publishing.{Artifact, Errors}

  describe "membership" do
    test "a member reads, changes, and publishes an Artifact" do
      user = user_fixture!()
      artifact = artifact_fixture!(user)

      assert {:ok, _} = Ash.get(Artifact, artifact.id, actor: user)
      assert {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)
    end

    test "a non-member gets not-found, never forbidden" do
      owner = user_fixture!()
      artifact = artifact_fixture!(owner)
      stranger = user_fixture!()

      assert {:error, error} = Ash.get(Artifact, artifact.id, actor: stranger)
      assert Errors.to_code(error) == "not_found"

      assert {:error, error} = Publishing.publish(artifact, "<p>2</p>", nil, actor: stranger)
      assert %Ash.Error.Forbidden{} = error
    end

    test "a User acting through a Harness reads with the User's rights and records the Harness" do
      user = user_fixture!()
      artifact = artifact_fixture!(user)
      harness = harness_fixture!(user)

      shared = %{shared: %{harness_id: harness.id, harness_name: harness.name}}
      assert {:ok, _} = Ash.get(Artifact, artifact.id, actor: user, context: shared)

      assert {:ok, artifact2} =
               Publishing.publish(artifact, "<p>2</p>", nil, actor: user, context: shared)

      version =
        Ash.get!(Publishing.Version, [artifact_id: artifact2.id, number: 2], authorize?: false)

      assert version.user_id == user.id
      assert version.harness_id == harness.id
    end

    test "a member adds another User to the Organization who then reads the Artifact" do
      owner = user_fixture!()
      organization = personal_organization!(owner)
      artifact = artifact_fixture!(owner)

      newcomer = user_fixture!()

      assert {:ok, _} =
               Accounts.add_member(organization.id, to_string(newcomer.email), actor: owner)

      assert {:ok, _} = Ash.get(Artifact, artifact.id, actor: newcomer)
    end
  end

  describe "agents" do
    test "an Agent of the Artifact's Organization reads and publishes" do
      owner = user_fixture!()
      organization = personal_organization!(owner)
      artifact = artifact_fixture!(owner)
      agent = agent_fixture!(organization, owner)

      assert {:ok, _} = Ash.get(Artifact, artifact.id, actor: agent)
      assert {:ok, _} = Publishing.publish(artifact, "<p>2</p>", nil, actor: agent)

      version =
        Ash.get!(Publishing.Version, [artifact_id: artifact.id, number: 2], authorize?: false)

      assert version.agent_id == agent.id
      assert version.user_id == nil
    end

    test "an Agent of a different Organization gets not-found" do
      owner = user_fixture!()
      artifact = artifact_fixture!(owner)

      other_owner = user_fixture!()
      other_organization = personal_organization!(other_owner)
      other_agent = agent_fixture!(other_organization, other_owner)

      assert {:error, error} = Ash.get(Artifact, artifact.id, actor: other_agent)
      assert Errors.to_code(error) == "not_found"
    end

    test "an Agent creates an Artifact in its own Organization" do
      owner = user_fixture!()
      organization = personal_organization!(owner)
      agent = agent_fixture!(organization, owner)

      assert {:ok, artifact} = Publishing.create_artifact("Board", html(), actor: agent)
      assert artifact.organization_id == organization.id
    end
  end

  describe "archived Artifacts stay readable" do
    test "a member still reads an archived Artifact's metadata, State, and History" do
      user = user_fixture!()
      artifact = artifact_fixture!(user)

      {:ok, _} =
        Publishing.change_state(artifact, [%{"op" => "set", "path" => "a", "value" => 1}],
          actor: user
        )

      {:ok, archived} = Publishing.archive(artifact, actor: user)

      assert {:ok, _} = Ash.get(Artifact, archived.id, actor: user)
      assert {:ok, %{"a" => 1}} = Publishing.get_state(archived.id, actor: user)
      assert {:ok, [_ | _]} = Publishing.history(archived.id, actor: user)
    end
  end
end
