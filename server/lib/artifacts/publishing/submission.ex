defmodule Artifacts.Publishing.Submission do
  @moduledoc """
  An Actor handing an Artifact's page back (DOMAIN.md §1.2): the State at
  that moment, an optional payload, the Version it was made on, and the
  Actor who made it. The `bigserial` id is the wait cursor
  (`Artifact.wait`).

  Create-only: no update or destroy action exists, its foreign keys
  restrict deletion, and a `BEFORE UPDATE OR DELETE` trigger on
  `submissions` refuses the statement even if one were attempted directly
  in SQL. Direct creation is forbidden; only `Artifact.submit`'s own
  `after_action` inserts a row, with `authorize?: false`.
  """

  use Ash.Resource,
    domain: Artifacts.Publishing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "submissions"
    repo Artifacts.Repo

    references do
      reference :artifact, on_delete: :restrict
      reference :user, on_delete: :restrict
      reference :agent, on_delete: :restrict
      reference :harness, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:user_id, :agent_id, :harness_id], "submissions_actor_shape_check",
        check: """
        (user_id IS NOT NULL) <> (agent_id IS NOT NULL)
        AND (harness_id IS NULL OR user_id IS NOT NULL)
        """
    end

    custom_statements do
      # Postgrex's extended query protocol refuses more than one command per
      # prepared statement, so the function and the trigger that invokes it
      # are two statements, not one.
      statement :refuse_change_function do
        up """
        CREATE FUNCTION submissions_refuse_change() RETURNS trigger AS $$
        BEGIN
          RAISE EXCEPTION 'submissions are append-only: % not allowed', TG_OP;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS submissions_refuse_change();"
      end

      statement :refuse_change_trigger do
        up """
        CREATE TRIGGER submissions_refuse_change
        BEFORE UPDATE OR DELETE ON submissions
        FOR EACH ROW EXECUTE FUNCTION submissions_refuse_change();
        """

        down "DROP TRIGGER IF EXISTS submissions_refuse_change ON submissions;"
      end
    end
  end

  attributes do
    integer_primary_key :id
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :state, Artifacts.Type.JSONValue, allow_nil?: false, public?: true
    attribute :payload, Artifacts.Type.JSONValue, allow_nil?: true, public?: true
    create_timestamp :inserted_at
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

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:artifact_id, :version, :state, :payload, :user_id, :agent_id, :harness_id]
    end
  end

  policies do
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
