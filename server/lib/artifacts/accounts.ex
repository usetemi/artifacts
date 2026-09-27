defmodule Artifacts.Accounts do
  @moduledoc """
  Identity and organizations (DOMAIN.md §1.1): Users, Organizations,
  Memberships, Harnesses, Agents, and AgentKeys.

  Every code interface below whose action creates a row (`create_agent`,
  `create_agent_key`, `create_harness`, `add_member`) takes the parent's id,
  not its struct, since the underlying action accepts a plain `:uuid`
  attribute. Every interface whose action updates or destroys a row
  (`remove_member`, `leave`, `revoke_agent_key`, `revoke_harness`) takes the
  record itself, which is how Ash's generated interface for an update or
  destroy action always works.
  """

  use Ash.Domain, otp_app: :artifacts

  resources do
    resource Artifacts.Accounts.User
    resource Artifacts.Accounts.UserIdentity
    resource Artifacts.Accounts.Token

    resource Artifacts.Accounts.Organization do
      define :list_organizations, action: :read
      define :create_organization, action: :create, args: [:name]
    end

    resource Artifacts.Accounts.Membership do
      define :add_member, action: :add_by_email, args: [:organization_id, :email]
      define :remove_member, action: :remove
      define :leave, action: :leave
    end

    resource Artifacts.Accounts.Harness do
      define :create_harness, action: :create, args: [:user_id, :name, :expires_at]
      define :revoke_harness, action: :revoke
    end

    resource Artifacts.Accounts.Agent do
      define :create_agent, action: :create, args: [:organization_id, :name]
    end

    resource Artifacts.Accounts.AgentKey do
      define :create_agent_key, action: :create, args: [:agent_id, :name, :expires_at]
      define :revoke_agent_key, action: :revoke
    end
  end
end
