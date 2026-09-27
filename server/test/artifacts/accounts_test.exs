defmodule Artifacts.AccountsTest do
  use Artifacts.DataCase, async: true

  require Ash.Query

  import Artifacts.AccountsFixtures

  alias Artifacts.Accounts
  alias Artifacts.Accounts.{Agent, Membership, Organization, User}

  defp api_key_actor(resource, plaintext_key) do
    resource
    |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: plaintext_key})
    |> Ash.read_one!(authorize?: false)
  end

  describe "register_with_google" do
    test "accepts a verified email and creates the Personal Organization" do
      user = user_fixture!(email: "victor@usetemi.com")

      assert to_string(user.email) == "victor@usetemi.com"
      assert user.personal_organization_id

      organization = personal_organization!(user)
      memberships = Ash.read!(Membership, actor: user)
      assert Enum.any?(memberships, &(&1.organization_id == organization.id))
    end

    test "rejects an unverified email and writes no User row" do
      email = unique_email()
      assert {:error, _error} = user_fixture(email: email, email_verified: false)

      assert Ash.count!(Ash.Query.filter(User, email == ^email), authorize?: false) == 0
    end

    test "rejects a disallowed domain and writes no User row" do
      # config/test.exs sets no SIGNUP_EMAIL_DOMAINS, so this asserts against
      # the reject change directly rather than the (permissive) app config.
      email = "someone@not-a-real-domain-#{System.unique_integer([:positive])}.example"

      Application.put_env(:artifacts, :signup_email_domains, "usetemi.com")

      try do
        assert {:error, _error} = user_fixture(email: email)
        assert Ash.count!(Ash.Query.filter(User, email == ^email), authorize?: false) == 0
      after
        Application.delete_env(:artifacts, :signup_email_domains)
      end
    end

    test "a repeat sign-in is a no-op" do
      email = unique_email()
      sub = "test-sub-#{System.unique_integer([:positive])}"
      user = user_fixture!(email: email, name: "First Name", sub: sub)
      organization_id = user.personal_organization_id

      user_again = user_fixture!(email: email, name: "Second Name", sub: sub)

      assert user_again.id == user.id
      assert user_again.personal_organization_id == organization_id
      # upsert_fields [] means name is not re-synced from Google either.
      assert user_again.name == "First Name"

      assert Ash.count!(Ash.Query.filter(Membership, organization_id == ^organization_id),
               authorize?: false
             ) == 1
    end
  end

  describe "create_organization" do
    test "the actor becomes its first Membership" do
      user = user_fixture!()
      organization = organization_fixture!(user)

      memberships = Ash.read!(Membership, actor: user)
      assert Enum.any?(memberships, &(&1.organization_id == organization.id))
    end

    test "is forbidden for an Agent actor" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.create_organization("Nope", actor: agent)
    end

    test "is forbidden for a nil actor" do
      assert {:error, %Ash.Error.Forbidden{}} = Accounts.create_organization("Nope", actor: nil)
    end
  end

  describe "a nil actor (neither User nor Agent) against a two-branch policy" do
    test "reading Organization is forbidden, not an empty result" do
      owner = user_fixture!()
      organization_fixture!(owner)

      assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Organization, actor: nil)
    end

    test "reading Agent is forbidden, not an empty result" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent_fixture!(organization, owner)

      assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Agent, actor: nil)
    end
  end

  describe "add_member" do
    test "adds an existing User by email" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      new_member = user_fixture!()

      assert {:ok, membership} =
               Accounts.add_member(organization.id, new_member.email, actor: owner)

      assert membership.user_id == new_member.id
      assert membership.organization_id == organization.id
    end

    test "fails for an unknown email" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)

      assert {:error, _error} =
               Accounts.add_member(organization.id, unique_email(), actor: owner)
    end

    test "is forbidden for a Harness-signed-in actor" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      new_member = user_fixture!()
      harness = harness_fixture!(owner)
      actor = api_key_actor(User, harness.__metadata__.plaintext_api_key)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.add_member(organization.id, new_member.email, actor: actor)
    end

    test "is forbidden for an Agent actor" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      new_member = user_fixture!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.add_member(organization.id, new_member.email, actor: agent)
    end
  end

  describe "remove_member and leave" do
    test "remove succeeds when more than one member remains" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      other = user_fixture!()
      {:ok, membership} = Accounts.add_member(organization.id, other.email, actor: owner)

      assert :ok = Accounts.remove_member(membership, actor: owner)

      assert Ash.count!(Ash.Query.filter(Membership, id == ^membership.id), authorize?: false) ==
               0
    end

    test "remove refuses the organization's last member" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)

      [membership] =
        Ash.read!(Ash.Query.filter(Membership, organization_id == ^organization.id),
          authorize?: false
        )

      assert {:error, _error} = Accounts.remove_member(membership, actor: owner)

      assert Ash.count!(Ash.Query.filter(Membership, id == ^membership.id), authorize?: false) ==
               1
    end

    test "remove is forbidden for a Harness-signed-in actor" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      other = user_fixture!()
      {:ok, membership} = Accounts.add_member(organization.id, other.email, actor: owner)
      harness = harness_fixture!(owner)
      actor = api_key_actor(User, harness.__metadata__.plaintext_api_key)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.remove_member(membership, actor: actor)
    end

    test "leave succeeds when more than one member remains" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      other = user_fixture!()
      {:ok, membership} = Accounts.add_member(organization.id, other.email, actor: owner)

      assert :ok = Accounts.leave(membership, actor: other)
    end

    test "leave refuses the organization's last member" do
      user = user_fixture!()
      organization = personal_organization!(user)

      [membership] =
        Ash.read!(Ash.Query.filter(Membership, organization_id == ^organization.id),
          authorize?: false
        )

      assert {:error, _error} = Accounts.leave(membership, actor: user)
    end

    test "leave is forbidden for a Harness-signed-in actor, even on their own membership" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      other = user_fixture!()
      {:ok, membership} = Accounts.add_member(organization.id, other.email, actor: owner)
      harness = harness_fixture!(other)
      actor = api_key_actor(User, harness.__metadata__.plaintext_api_key)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.leave(membership, actor: actor)

      assert Ash.count!(Ash.Query.filter(Membership, id == ^membership.id), authorize?: false) ==
               1
    end
  end

  describe "Agent creation and AgentKey issue/revoke" do
    test "a member creates an Agent" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)

      assert {:ok, agent} = Accounts.create_agent(organization.id, "Pidgey", actor: owner)
      assert agent.organization_id == organization.id
    end

    test "create_agent is forbidden for a non-member" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      outsider = user_fixture!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.create_agent(organization.id, "Pidgey", actor: outsider)
    end

    test "create_agent is forbidden for an Agent actor" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.create_agent(organization.id, "Another", actor: agent)
    end

    test "create_agent_key issues a key whose plaintext is shown once, then revoke_agent_key revokes it" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      expires_at = DateTime.add(DateTime.utc_now(), 365, :day)

      assert {:ok, agent_key} =
               Accounts.create_agent_key(agent.id, "key one", expires_at, actor: owner)

      assert is_binary(agent_key.__metadata__.plaintext_api_key)
      assert String.starts_with?(agent_key.__metadata__.plaintext_api_key, "arta_")
      refute agent_key.revoked_at

      assert {:ok, revoked} = Accounts.revoke_agent_key(agent_key, actor: owner)
      assert revoked.revoked_at
    end
  end

  describe "Harness create and revoke" do
    test "a User creates and revokes their own Harness" do
      user = user_fixture!()
      expires_at = DateTime.add(DateTime.utc_now(), 365, :day)

      assert {:ok, harness} =
               Accounts.create_harness(user.id, "Claude Code", expires_at, actor: user)

      assert String.starts_with?(harness.__metadata__.plaintext_api_key, "arth_")

      assert {:ok, revoked} = Accounts.revoke_harness(harness, actor: user)
      assert revoked.revoked_at
    end

    test "create_harness is forbidden for a Harness-signed-in actor" do
      user = user_fixture!()
      harness = harness_fixture!(user)
      actor = api_key_actor(User, harness.__metadata__.plaintext_api_key)
      expires_at = DateTime.add(DateTime.utc_now(), 365, :day)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.create_harness(user.id, "Another", expires_at, actor: actor)
    end
  end

  describe "sign_in_with_api_key round trips" do
    test "a valid Harness key resolves the User, revoked and expired keys fail" do
      user = user_fixture!()
      harness = harness_fixture!(user)
      key = harness.__metadata__.plaintext_api_key

      resolved = api_key_actor(User, key)
      assert resolved.id == user.id
      assert resolved.__metadata__.using_api_key?
      assert resolved.__metadata__.api_key.id == harness.id

      {:ok, _} = Accounts.revoke_harness(harness, actor: user)
      assert api_key_actor(User, key) == nil

      expired_harness =
        harness_fixture!(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :day))

      assert api_key_actor(User, expired_harness.__metadata__.plaintext_api_key) == nil
    end

    test "a valid Agent key resolves the Agent, revoked and expired keys fail" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      agent_key = agent_key_fixture!(agent, owner)
      key = agent_key.__metadata__.plaintext_api_key

      resolved = api_key_actor(Agent, key)
      assert resolved.id == agent.id
      assert resolved.__metadata__.using_api_key?

      {:ok, _} = Accounts.revoke_agent_key(agent_key, actor: owner)
      assert api_key_actor(Agent, key) == nil

      expired_key =
        agent_key_fixture!(agent, owner, expires_at: DateTime.add(DateTime.utc_now(), -1, :day))

      assert api_key_actor(Agent, expired_key.__metadata__.plaintext_api_key) == nil
    end
  end

  describe "non-member reads return not found" do
    test "a non-member reading an Organization by id gets not found, not forbidden" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      outsider = user_fixture!()

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Organization, organization.id, actor: outsider)
    end

    test "a non-member reading an Agent by id gets not found" do
      owner = user_fixture!()
      organization = organization_fixture!(owner)
      agent = agent_fixture!(organization, owner)
      outsider = user_fixture!()

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Agent, agent.id, actor: outsider)
    end

    test "an unrelated Agent reading another organization's Agent gets not found" do
      owner_a = user_fixture!()
      org_a = organization_fixture!(owner_a)
      agent_a = agent_fixture!(org_a, owner_a)

      owner_b = user_fixture!()
      org_b = organization_fixture!(owner_b)
      agent_b = agent_fixture!(org_b, owner_b)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Agent, agent_a.id, actor: agent_b)
    end
  end
end
