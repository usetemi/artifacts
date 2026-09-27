defmodule Artifacts.Accounts.User do
  @moduledoc """
  A person with an account on the Instance, signed in with Google
  (DOMAIN.md §1.1). A `Harness` signs a User in with an API key instead of
  a session; either way, policies see the same `User` struct, distinguished
  by `__metadata__.using_api_key?` (set only for the Harness path).
  """

  use Ash.Resource,
    otp_app: :artifacts,
    domain: Artifacts.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "users"
    repo Artifacts.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :personal_organization, Artifacts.Accounts.Organization do
      public? true
      allow_nil? true
    end

    has_many :memberships, Artifacts.Accounts.Membership
    has_many :harnesses, Artifacts.Accounts.Harness

    has_many :valid_api_keys, Artifacts.Accounts.Harness do
      filter expr(is_nil(revoked_at) and expires_at > now())
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  authentication do
    tokens do
      enabled? true
      token_resource Artifacts.Accounts.Token
      signing_secret Artifacts.Accounts.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      google do
        client_id Artifacts.Accounts.Secrets
        client_secret Artifacts.Accounts.Secrets
        redirect_uri Artifacts.Accounts.Secrets
        identity_resource Artifacts.Accounts.UserIdentity
      end

      api_key do
        api_key_relationship :valid_api_keys
      end
    end
  end

  actions do
    defaults [:read]

    create :register_with_google do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true

      upsert? true
      upsert_identity :unique_email
      # A matched row's columns are left untouched entirely, so a repeat
      # sign-in returns the row's already-persisted state (personal
      # organization included) rather than re-syncing name/email from
      # Google.
      upsert_fields []

      change Artifacts.Accounts.User.Changes.RejectUnverifiedOrDisallowedDomain

      change fn changeset, _context ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        Ash.Changeset.change_attributes(changeset, %{
          email: user_info["email"],
          name: user_info["name"]
        })
      end

      change AshAuthentication.GenerateTokenChange
      # Persists the iss/sub identity claims the verifier requires now that
      # identity_resource is configured (see Artifacts.Accounts.UserIdentity).
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change Artifacts.Accounts.User.Changes.CreatePersonalOrganization
    end

    # Internal only: called from `CreatePersonalOrganization`'s after_action
    # with `authorize?: false`. Never exposed as a public code interface.
    update :set_personal_organization do
      accept [:personal_organization_id]
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  policies do
    # Lets AshAuthentication's own internal reads/writes (register, sign-in
    # with API key, token issuance) run regardless of the policies below.
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
    end
  end
end
