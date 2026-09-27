defmodule Artifacts.Accounts.Membership do
  @moduledoc """
  A User's belonging to an Organization. Every member has the same rights
  (DOMAIN.md §1.1). An Organization always keeps at least one member, so
  its last Membership can be neither removed nor left
  (`Artifacts.Accounts.Membership.Validations.NotLastMember`).
  """

  use Ash.Resource,
    domain: Artifacts.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Artifacts.Repo
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :user, Artifacts.Accounts.User, allow_nil?: false
    belongs_to :organization, Artifacts.Accounts.Organization, allow_nil?: false
  end

  identities do
    identity :unique_membership, [:user_id, :organization_id]
  end

  validations do
    validate Artifacts.Accounts.Membership.Validations.NotLastMember,
      on: [:destroy],
      before_action?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:user_id, :organization_id]
    end

    create :add_by_email do
      accept [:organization_id]
      argument :email, :ci_string, allow_nil?: false
      change Artifacts.Accounts.Membership.Changes.SetUserByEmail
    end

    destroy :remove do
      accept []
      # The NotLastMember validation reads other rows, so it can't be
      # folded into a single atomic SQL statement.
      require_atomic? false
    end

    destroy :leave do
      accept []
      require_atomic? false
    end
  end

  policies do
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

    policy action(:add_by_email) do
      forbid_if AshAuthentication.Checks.UsingApiKey
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy action(:remove) do
      forbid_if AshAuthentication.Checks.UsingApiKey
      forbid_if Artifacts.Accounts.Checks.ActorIsAgent
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy action(:leave) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end
end
