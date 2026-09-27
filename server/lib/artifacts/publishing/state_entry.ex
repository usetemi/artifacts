defmodule Artifacts.Publishing.StateEntry do
  @moduledoc """
  One leaf of an Artifact's shared State (DOMAIN.md §1.2): a JSON document
  assembled from rows, one row per leaf at a dotted path. `Artifacts.State`
  owns the path/leaf rules; this resource just stores the rows.

  Unlike `Version`/`Submission`/`Event`, State is mutable — a `set`
  upserts a leaf and a `delete` removes a subtree — so there is no
  append-only trigger here. Direct creation and destruction are forbidden;
  only `Artifact.change_state`'s own `after_action` writes rows, with
  `authorize?: false`.
  """

  use Ash.Resource,
    domain: Artifacts.Publishing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "state_entries"
    repo Artifacts.Repo

    references do
      reference :artifact, on_delete: :restrict
      reference :user, on_delete: :restrict
      reference :agent, on_delete: :restrict
      reference :harness, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:user_id, :agent_id, :harness_id], "state_entries_actor_shape_check",
        check: """
        (user_id IS NOT NULL) <> (agent_id IS NOT NULL)
        AND (harness_id IS NULL OR user_id IS NOT NULL)
        """
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :path, :string, allow_nil?: false, public?: true
    attribute :value, Artifacts.Type.JSONValue, allow_nil?: false, public?: true
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :artifact, Artifacts.Publishing.Artifact,
      allow_nil?: false,
      attribute_writable?: true,
      attribute_type: :string

    belongs_to :user, Artifacts.Accounts.User, allow_nil?: true, attribute_writable?: true
    belongs_to :agent, Artifacts.Accounts.Agent, allow_nil?: true, attribute_writable?: true
    belongs_to :harness, Artifacts.Accounts.Harness, allow_nil?: true, attribute_writable?: true
  end

  identities do
    identity :unique_artifact_path, [:artifact_id, :path]
  end

  actions do
    defaults [:read]

    create :upsert do
      primary? true
      accept [:artifact_id, :path, :value, :updated_at, :user_id, :agent_id, :harness_id]
      upsert? true
      upsert_identity :unique_artifact_path
      upsert_fields [:value, :updated_at, :user_id, :agent_id, :harness_id]
    end

    destroy :destroy do
      primary? true
      accept []
    end
  end

  policies do
    policy action_type(:create) do
      forbid_if always()
    end

    policy action_type(:destroy) do
      forbid_if always()
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(artifact.organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(artifact.organization_id == ^actor(:organization_id))
    end
  end
end
