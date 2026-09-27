defmodule Artifacts.AccountsFixtures do
  @moduledoc """
  Test fixtures for `Artifacts.Accounts`, built through the real actions
  (`register_with_google`, `create_organization`, `create_agent`, ...) so a
  fixture exercises the same changes and policies production code does.
  """

  alias Artifacts.Accounts

  def unique_email, do: "user#{System.unique_integer([:positive])}@usetemi.com"

  @doc """
  Registers a User via `register_with_google`, bypassing authorization the
  way an OAuth2 callback would (there is no actor yet). Returns the User,
  with its Personal Organization already created.
  """
  def user_fixture(opts \\ []) do
    email = Keyword.get(opts, :email, unique_email())
    name = Keyword.get(opts, :name, "Test User")
    email_verified = Keyword.get(opts, :email_verified, true)
    sub = Keyword.get(opts, :sub, "test-sub-#{System.unique_integer([:positive])}")

    Artifacts.Accounts.User
    |> Ash.Changeset.for_create(
      :register_with_google,
      %{
        user_info: %{
          "sub" => sub,
          "email" => email,
          "email_verified" => email_verified,
          "name" => name
        },
        oauth_tokens: %{"access_token" => "test-token"}
      },
      authorize?: false
    )
    |> Ash.create()
  end

  def user_fixture!(opts \\ []) do
    {:ok, user} = user_fixture(opts)
    user
  end

  @doc "The User's Personal Organization, loaded with `authorize?: false`."
  def personal_organization!(user) do
    Ash.get!(Artifacts.Accounts.Organization, user.personal_organization_id, authorize?: false)
  end

  def organization_fixture!(actor, opts \\ []) do
    name = Keyword.get(opts, :name, "Test Org #{System.unique_integer([:positive])}")
    Accounts.create_organization!(name, actor: actor)
  end

  def agent_fixture!(organization, actor, opts \\ []) do
    name = Keyword.get(opts, :name, "Test Agent")
    Accounts.create_agent!(organization.id, name, actor: actor)
  end

  def agent_key_fixture!(agent, actor, opts \\ []) do
    name = Keyword.get(opts, :name, "Test Agent Key")
    expires_at = Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 365, :day))
    Accounts.create_agent_key!(agent.id, name, expires_at, actor: actor)
  end

  def harness_fixture!(user, opts \\ []) do
    name = Keyword.get(opts, :name, "Test Harness")
    expires_at = Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 365, :day))
    Accounts.create_harness!(user.id, name, expires_at, actor: user)
  end
end
