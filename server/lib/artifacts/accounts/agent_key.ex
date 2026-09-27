defmodule Artifacts.Accounts.AgentKey do
  @moduledoc """
  One of an Agent's keys (DOMAIN.md §1.1). Any member of the Agent's
  Organization issues and revokes them.
  """

  use Ash.Resource,
    domain: Artifacts.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agent_keys"
    repo Artifacts.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :api_key_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :agent, Artifacts.Accounts.Agent, allow_nil?: false
  end

  calculations do
    calculate :valid, :boolean, expr(is_nil(revoked_at) and expires_at > now())
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:agent_id, :name, :expires_at]

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey,
              prefix: :arta, hash: :api_key_hash}
    end

    update :revoke do
      accept []
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end
  end

  policies do
    # Lets AshAuthentication's own sign-in-with-api-key read of the
    # `valid_agent_keys` relationship (on `Artifacts.Accounts.Agent`) run
    # regardless of the policies below.
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(agent.organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(agent_id == ^actor(:id))
    end

    policy action(:create) do
      forbid_if AshAuthentication.Checks.UsingApiKey
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if expr(exists(agent.organization.memberships, user_id == ^actor(:id)))
    end

    policy action(:revoke) do
      forbid_if AshAuthentication.Checks.UsingApiKey
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if expr(exists(agent.organization.memberships, user_id == ^actor(:id)))
    end
  end
end
