defmodule Artifacts.Publishing.Event do
  @moduledoc """
  One recorded change to an Artifact's content (DOMAIN.md §1.3): a Version
  Published, a State Changed, or a Submission Made. The `bigserial` id is
  the History order. `data` holds a pointer, not a copy (DESIGN.md
  "Content changes"): `{number}` for `version_published`, the ops list for
  `state_changed`, `{submission_id}` for `submission_made`.

  Create-only: no update or destroy action exists, its foreign keys
  restrict deletion, and a `BEFORE UPDATE OR DELETE` trigger on `events`
  refuses the statement even if one were attempted directly in SQL. Direct
  creation is forbidden; only `Artifact`'s content actions insert a row,
  with `authorize?: false`, one per action call.
  """

  use Ash.Resource,
    domain: Artifacts.Publishing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "events"
    repo Artifacts.Repo

    references do
      reference :artifact, on_delete: :restrict
      reference :user, on_delete: :restrict
      reference :agent, on_delete: :restrict
      reference :harness, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:user_id, :agent_id, :harness_id], "events_actor_shape_check",
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
        CREATE FUNCTION events_refuse_change() RETURNS trigger AS $$
        BEGIN
          RAISE EXCEPTION 'events are append-only: % not allowed', TG_OP;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS events_refuse_change();"
      end

      statement :refuse_change_trigger do
        up """
        CREATE TRIGGER events_refuse_change
        BEFORE UPDATE OR DELETE ON events
        FOR EACH ROW EXECUTE FUNCTION events_refuse_change();
        """

        down "DROP TRIGGER IF EXISTS events_refuse_change ON events;"
      end
    end
  end

  attributes do
    integer_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:version_published, :state_changed, :submission_made]
    end

    attribute :data, Artifacts.Type.JSONValue, allow_nil?: false, public?: true
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
      accept [:artifact_id, :kind, :data, :user_id, :agent_id, :harness_id]
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
