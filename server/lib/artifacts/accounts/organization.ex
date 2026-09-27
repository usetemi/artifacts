defmodule Artifacts.Accounts.Organization do
  @moduledoc """
  The unit of ownership and sharing (DOMAIN.md §1.1). Every Artifact
  belongs to exactly one Organization, and every Actor that can work on it
  is a member of that Organization or acts for one.
  """

  use Ash.Resource,
    domain: Artifacts.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Artifacts.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  relationships do
    has_many :memberships, Artifacts.Accounts.Membership
    has_many :agents, Artifacts.Accounts.Agent
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name]
      change Artifacts.Accounts.Organization.Changes.CreateFirstMembership
    end
  end

  policies do
    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(id == ^actor(:organization_id))
    end

    policy action(:create) do
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if actor_present()
    end
  end
end
