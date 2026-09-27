defmodule Artifacts.Publishing.Version do
  @moduledoc """
  One immutable HTML document published to an Artifact (DOMAIN.md §1.2).
  Versions are numbered in order; the latest is the Artifact's
  `current_version`, which its URL serves.

  Create-only: no update or destroy action exists, its foreign keys
  restrict deletion, and a `BEFORE UPDATE OR DELETE` trigger on `versions`
  refuses the statement even if one were attempted directly in SQL.
  Direct creation is forbidden; only `Artifact`'s own `create`/`publish`
  actions insert a row here, with `authorize?: false` from their own
  `after_action`.
  """

  use Ash.Resource,
    domain: Artifacts.Publishing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "versions"
    repo Artifacts.Repo

    references do
      reference :artifact, on_delete: :restrict
      reference :user, on_delete: :restrict
      reference :agent, on_delete: :restrict
      reference :harness, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:user_id, :agent_id, :harness_id], "versions_actor_shape_check",
        check: """
        (user_id IS NOT NULL) <> (agent_id IS NOT NULL)
        AND (harness_id IS NULL OR user_id IS NOT NULL)
        """
    end

    custom_statements do
      # Postgrex's extended query protocol refuses more than one command per
      # prepared statement, so the function and the trigger that invokes it
      # are two statements, not one — "Custom statements on the same table
      # run in declaration order" (ash_postgres), so the function exists
      # before the trigger is created.
      statement :refuse_change_function do
        up """
        CREATE FUNCTION versions_refuse_change() RETURNS trigger AS $$
        BEGIN
          RAISE EXCEPTION 'versions are append-only: % not allowed', TG_OP;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS versions_refuse_change();"
      end

      statement :refuse_change_trigger do
        up """
        CREATE TRIGGER versions_refuse_change
        BEFORE UPDATE OR DELETE ON versions
        FOR EACH ROW EXECUTE FUNCTION versions_refuse_change();
        """

        down "DROP TRIGGER IF EXISTS versions_refuse_change ON versions;"
      end
    end
  end

  attributes do
    attribute :number, :integer, allow_nil?: false, primary_key?: true, public?: true
    attribute :html, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :artifact, Artifacts.Publishing.Artifact,
      primary_key?: true,
      allow_nil?: false,
      attribute_writable?: true,
      attribute_type: :string

    belongs_to :user, Artifacts.Accounts.User, allow_nil?: true, attribute_writable?: true
    belongs_to :agent, Artifacts.Accounts.Agent, allow_nil?: true, attribute_writable?: true
    belongs_to :harness, Artifacts.Accounts.Harness, allow_nil?: true, attribute_writable?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:artifact_id, :number, :html, :user_id, :agent_id, :harness_id]
    end
  end

  policies do
    # No caller creates a Version directly: `Artifact.create`/`publish` do,
    # from their own `after_action`, with `authorize?: false`.
    policy action_type(:create) do
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
