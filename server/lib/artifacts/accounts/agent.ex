defmodule Artifacts.Accounts.Agent do
  @moduledoc """
  A coworker agent that belongs to exactly one Organization and acts as
  itself, not as any person (DOMAIN.md §1.1). A member of its Organization
  creates it and issues its keys. Its own AshAuthentication api_key
  strategy issues no tokens (`tokens.token_resource false`) — an Agent
  authenticates for one request at a time, never a browser session.
  """

  use Ash.Resource,
    otp_app: :artifacts,
    domain: Artifacts.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agents"
    repo Artifacts.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, Artifacts.Accounts.Organization, allow_nil?: false

    has_many :agent_keys, Artifacts.Accounts.AgentKey

    has_many :valid_agent_keys, Artifacts.Accounts.AgentKey do
      filter expr(is_nil(revoked_at) and expires_at > now())
    end
  end

  authentication do
    tokens do
      token_resource false
    end

    strategies do
      api_key do
        api_key_relationship :valid_agent_keys
      end
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:organization_id, :name]
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action(:create) do
      forbid_if AshAuthentication.Checks.UsingApiKey
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end
  end
end
