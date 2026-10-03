defmodule Artifacts.Publishing.Artifact do
  @moduledoc """
  One live page with a stable identity and URL (DOMAIN.md §1.2): its
  Versions, its State, its Submissions, and its History. The aggregate
  root — every content action runs on it, writing the child row and its
  Event together in one transaction (DESIGN.md "Content changes").

  The id is a 22-char URL-safe random string (`generate_id/0`), not an
  Ash builtin id type: `Base.url_encode64(padding: false)` of 16 random
  bytes.
  """

  use Ash.Resource,
    domain: Artifacts.Publishing,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Artifacts.Publishing.ChannelNotifier]

  alias Artifacts.Publishing.Artifact.Changes.{
    ChangeState,
    PublishFirstVersion,
    Publish,
    ResolveOrganization,
    Submit
  }

  alias Artifacts.Publishing.Artifact.Validations.HtmlSize
  alias Artifacts.Publishing.{Actor, Errors, Event, StateEntry, Submission, Version}
  alias Artifacts.State

  require Ash.Query

  postgres do
    table "artifacts"
    repo Artifacts.Repo

    references do
      reference :organization, on_delete: :restrict
    end
  end

  json_api do
    type "artifact"
  end

  attributes do
    attribute :id, :string do
      primary_key? true
      allow_nil? false
      writable? false
      public? true
      default &Artifacts.Publishing.Artifact.generate_id/0
      constraints max_length: 22, min_length: 22
    end

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :current_version, :integer, allow_nil?: false, default: 0, public?: true
    attribute :archived_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Artifacts.Accounts.Organization, allow_nil?: false

    has_many :versions, Artifacts.Publishing.Version
    has_many :state_entries, Artifacts.Publishing.StateEntry
    has_many :submissions, Artifacts.Publishing.Submission
    has_many :events, Artifacts.Publishing.Event
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept []
      description "Create a new Artifact and publish its first Version."

      argument :title, :string do
        allow_nil? false
        constraints min_length: 1
        description "The new Artifact's title."
      end

      argument :html, :string do
        allow_nil? false
        description "The page's full HTML for the first Version."
      end

      argument :organization_id, :uuid do
        allow_nil? true

        description "The Organization to create the Artifact in. Defaults to the actor's Personal Organization, or an Agent's own Organization."
      end

      change set_attribute(:title, arg(:title))
      change set_attribute(:current_version, 0)
      change ResolveOrganization
      change PublishFirstVersion
    end

    update :publish do
      accept []
      description "Publish a new Version of the Artifact."

      argument :html, :string do
        allow_nil? false
        description "The page's full HTML for the new Version."
      end

      argument :if_version, :integer do
        allow_nil? true

        description "Compare-and-set: publish only if the Artifact's current_version still equals this number, else fail with a \"conflict\" error. Omit to publish unconditionally."
      end

      require_atomic? false

      validate HtmlSize

      change Publish
    end

    update :change_state do
      accept []

      description """
      Apply one or more operations to the Artifact's State in one transaction. State is a JSON object assembled from rows, one per leaf at a dotted path. Each op is {"op": "set", "path": ..., "value": ...} or {"op": "delete", "path": ...}: setting a path replaces every leaf at or below it with the leaves of the new value, and deleting a path removes it and everything below it. Setting a value of null is normalized to a delete. Arrays are one leaf — key items individually (e.g. "items.<id>") to edit them without replacing the whole array. A path is at most 1000 bytes, with no empty segment and no whitespace.
      """

      argument :ops, {:array, :map} do
        allow_nil? false

        description "The operations to apply, in order: each is {op: \"set\", path, value} or {op: \"delete\", path}. Within one call, the last write to a given path wins."
      end

      require_atomic? false

      change ChangeState
    end

    update :submit do
      accept []

      description "Hand the Artifact back with an optional payload, recorded as a Submission a waiting `wait` call can pick up."

      argument :payload, Artifacts.Type.JSONValue do
        allow_nil? true

        description "Arbitrary JSON to attach to the Submission. Optional; omit for a bare hand-back."
      end

      require_atomic? false

      change Submit
    end

    read :list do
      description "Open Artifacts in one Organization, most recently updated first. Pass archived: true to list archived ones instead."

      argument :organization_id, :uuid do
        allow_nil? false
        description "The Organization to list Artifacts in."
      end

      argument :archived, :boolean do
        allow_nil? true
        default false
        description "true lists archived Artifacts instead of open ones. Defaults to false."
      end

      # Unlike a generic action's `Ash.ActionInput` (`wait`, `history`,
      # `get_artifact`), `Ash.Query`'s own `default:` handling fills only
      # a wholly omitted argument, never an explicit `null` — and
      # `^arg(:archived)` below, resolved into a SQL comparison after
      # preparations run, would fail both its branches under SQL's
      # three-valued logic and return nothing. This normalizes an
      # explicit `null` to `false` before the filter runs.
      prepare fn query, _context ->
        Ash.Query.set_argument(
          query,
          :archived,
          Ash.Query.get_argument(query, :archived) || false
        )
      end

      filter expr(
               organization_id == ^arg(:organization_id) and
                 ((^arg(:archived) == false and is_nil(archived_at)) or
                    (^arg(:archived) == true and not is_nil(archived_at)))
             )

      prepare build(sort: [updated_at: :desc])
    end

    update :rename do
      accept [:title]
      require_attributes [:title]
      description "Change the Artifact's title."
      require_atomic? false
      validate string_length(:title, min: 1)
    end

    update :archive do
      accept []

      description "Close the Artifact: it stays readable, but no further Version, State, or Submission changes can be made until it is unarchived."

      require_atomic? false

      change fn changeset, _context ->
        case changeset.data.archived_at do
          nil -> Ash.Changeset.force_change_attribute(changeset, :archived_at, DateTime.utc_now())
          _already -> changeset
        end
      end
    end

    update :unarchive do
      accept []
      description "Reopen an archived Artifact so it accepts content changes again."
      change set_attribute(:archived_at, nil)
    end

    action :get_state, :map do
      description "The Artifact's current State, expanded from its stored dotted-path leaves into a nested JSON object."

      argument :artifact_id, :string do
        allow_nil? false
        description "The Artifact's id."
      end

      run fn input, context -> get_state(input, context) end
    end

    # Distinct from `get_state`: this returns the flat, dotted-path leaves
    # (`%{"a.b" => 1}`), the shape the page channel's join reply and
    # `state:ops` push carry, and `runtime.js`'s `applyOps`/`state.js`
    # algebra operates on. `get_state`'s expanded nested object is for a
    # human or agent reading state through MCP/HTTP, not for reapplying
    # ops to. Not exposed as its own MCP tool or JSON:API route.
    action :get_leaves, :map do
      argument :artifact_id, :string, allow_nil?: false

      run fn input, context -> get_leaves(input, context) end
    end

    action :wait, {:array, :struct} do
      constraints items: [instance_of: Artifacts.Publishing.Submission]

      description "Block until a new Submission is made on the Artifact, or until timeout elapses, then return the Submissions made since the given cursor. Call again passing the last Submission id you saw as since."

      argument :artifact_id, :string do
        allow_nil? false
        description "The Artifact's id."
      end

      argument :since, :integer do
        allow_nil? true

        description "Return Submissions with id greater than this. Omit to wait only for Submissions made after this call started, skipping any that already existed."
      end

      argument :timeout, :integer do
        allow_nil? true
        default 45_000

        description "Milliseconds to block before returning an empty list if nothing arrives. Defaults to 45000; capped at 50000."
      end

      transaction? false

      run fn input, context -> wait(input, context) end
    end

    action :history, {:array, :map} do
      description "One page of the Artifact's History: its Events (Version published, State changed, Submission made) in id order, after a cursor."

      argument :artifact_id, :string do
        allow_nil? false
        description "The Artifact's id."
      end

      argument :after, :integer do
        allow_nil? true
        default 0

        description "Return Events with id greater than this. Defaults to 0, the start of History."
      end

      argument :limit, :integer do
        allow_nil? true
        default 50
        description "Maximum number of Events to return. Defaults to 50; capped at 200."
      end

      argument :include_html, :boolean do
        allow_nil? true
        default false

        description "For a Version-published Event, include that Version's full HTML in the result. Defaults to false."
      end

      run fn input, context -> history(input, context) end
    end

    action :get_guide, :string do
      description "The full guide to using Artifacts: the publish/wait loop, the page API (window.artifact), the page CSP, caps, error codes, and a complete example page. Call once before your first publish_artifact."

      run fn _input, _context -> {:ok, Artifacts.Guide.text()} end
    end

    action :get_artifact, :map do
      description "The Artifact's metadata — id, title, Organization, current Version number, and archived status — and, when requested, one Version's HTML."

      argument :artifact_id, :string do
        allow_nil? false
        description "The Artifact's id."
      end

      argument :version, :integer do
        allow_nil? true
        description "Which Version to report on. Defaults to the Artifact's current Version."
      end

      argument :include_html, :boolean do
        allow_nil? true
        default false
        description "Include that Version's HTML in the result. Defaults to false."
      end

      run fn input, context -> get_artifact(input, context) end
    end

    action :publish_artifact, :struct do
      constraints instance_of: Artifacts.Publishing.Artifact

      description "Create a new Artifact, or publish a new Version to an existing one. Omit artifact_id to create; pass it to publish a Version onto that Artifact instead."

      argument :artifact_id, :string do
        allow_nil? true

        description "Omit to create a new Artifact; pass an existing Artifact's id to publish a new Version onto it instead."
      end

      argument :title, :string do
        allow_nil? true
        constraints min_length: 1
        description "The new Artifact's title. Used only when creating (artifact_id omitted)."
      end

      argument :html, :string do
        allow_nil? false
        description "The page's full HTML for the new Version."
      end

      argument :if_version, :integer do
        allow_nil? true

        description "Compare-and-set: publish only if the Artifact's current_version still equals this number, else fail with a \"conflict\" error. Omit to publish unconditionally. Used only when publishing (artifact_id present)."
      end

      argument :organization_id, :uuid do
        allow_nil? true

        description "The Organization to create the Artifact in. Used only when creating; defaults to the actor's Personal Organization, or an Agent's own Organization."
      end

      run fn input, context -> publish_artifact(input, context) end
    end
  end

  policies do
    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:read), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy [action_type(:create), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:create), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy [action_type(:update), Artifacts.Accounts.Checks.ActorIsUser] do
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy [action_type(:update), Artifacts.Accounts.Checks.ActorIsAgent] do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    # Generic actions have no record to filter, so this only lets any
    # authenticated actor through the DSL gate; each one's `run/2` body
    # re-checks membership itself with `Ash.get/3` under the real actor,
    # which is what actually turns a non-member's call into not-found.
    policy action_type(:action) do
      authorize_if actor_present()
    end
  end

  @doc """
  22 URL-safe base64 characters from 16 random bytes — the Artifact id.
  Referenced by the `id` attribute's `default`.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  ## Generic action bodies

  defp read_opts(context) do
    shared = (context.source_context || %{})[:shared] || %{}
    [actor: context.actor, context: %{shared: shared}]
  end

  # `Ash.get/3`'s own `Ash.Error.Query.NotFound` already resolves to the
  # "not_found" code (`Errors.to_code/1`), but `ash_ai`'s own
  # `AshAi.ToToolError` impl for that exact struct renders it as "could not
  # be found" — a built-in impl this app cannot redefine (module
  # redefinition, fails `--warnings-as-errors`). Every generic action that
  # looks up its own Artifact goes through this instead, so an MCP tool
  # call's error text is the stable code (`Errors.NotFound`, this app's
  # own struct, DOES get its own `AshAi.ToToolError` impl).
  defp get_owned_artifact(artifact_id, context) do
    case Ash.get(__MODULE__, artifact_id, read_opts(context)) do
      {:ok, artifact} ->
        {:ok, artifact}

      {:error, error} ->
        if Errors.to_code(error) == "not_found" do
          {:error, Errors.NotFound.exception(artifact_id: artifact_id)}
        else
          {:error, error}
        end
    end
  end

  defp get_state(input, context) do
    with {:ok, leaves} <- read_leaves(input, context) do
      {:ok, State.expand(leaves)}
    end
  end

  defp get_leaves(input, context), do: read_leaves(input, context)

  defp read_leaves(input, context) do
    artifact_id = input.arguments.artifact_id

    with {:ok, _artifact} <- get_owned_artifact(artifact_id, context) do
      leaves =
        StateEntry
        |> Ash.Query.filter(artifact_id == ^artifact_id)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.path, &1.value})

      {:ok, leaves}
    end
  end

  defp wait(input, context) do
    artifact_id = input.arguments.artifact_id
    # A generic action's own `default:` applies for an explicit `null`
    # too, not only a wholly omitted argument (`Ash.ActionInput.
    # set_defaults/1`, unlike `Ash.Query`'s), so `timeout` is never `nil`
    # here even though the argument is now optional.
    timeout = min(input.arguments.timeout, 50_000)

    with {:ok, _artifact} <- get_owned_artifact(artifact_id, context) do
      topic = "artifact:#{artifact_id}"
      :ok = Phoenix.PubSub.subscribe(Artifacts.PubSub, topic)

      try do
        since = Map.get(input.arguments, :since) || latest_submission_id(artifact_id)
        deadline = System.monotonic_time(:millisecond) + timeout
        poll_wait(artifact_id, since, deadline)
      after
        Phoenix.PubSub.unsubscribe(Artifacts.PubSub, topic)
      end
    end
  end

  defp poll_wait(artifact_id, since, deadline) do
    case submissions_since(artifact_id, since) do
      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:ok, []}
        else
          receive do
            {:version, _} -> poll_wait(artifact_id, since, deadline)
            {:state_ops, _} -> poll_wait(artifact_id, since, deadline)
            {:submission, _} -> poll_wait(artifact_id, since, deadline)
          after
            remaining -> {:ok, []}
          end
        end

      found ->
        {:ok, found}
    end
  end

  defp submissions_since(artifact_id, since) do
    Submission
    |> Ash.Query.filter(artifact_id == ^artifact_id and id > ^since)
    |> Ash.Query.sort(id: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp latest_submission_id(artifact_id) do
    Submission
    |> Ash.Query.filter(artifact_id == ^artifact_id)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [%{id: id}] -> id
      [] -> 0
    end
  end

  @max_history_page 200

  defp history(input, context) do
    artifact_id = input.arguments.artifact_id
    # Same reasoning as `wait`'s `timeout`: `after` and `limit` are never
    # `nil` here, defaulted or not.
    after_id = input.arguments.after
    limit = min(input.arguments.limit, @max_history_page)

    with {:ok, _artifact} <- get_owned_artifact(artifact_id, context) do
      events =
        Event
        |> Ash.Query.filter(artifact_id == ^artifact_id and id > ^after_id)
        |> Ash.Query.sort(id: :asc)
        |> Ash.Query.limit(limit)
        |> Ash.read!(authorize?: false)

      {:ok, Enum.map(events, &resolve_event(&1, input.arguments.include_html))}
    end
  end

  defp resolve_event(
         %Event{kind: :version_published, data: %{"number" => number}} = event,
         include_html
       ) do
    data =
      if include_html do
        version =
          Ash.get!(Version, [artifact_id: event.artifact_id, number: number], authorize?: false)

        %{number: number, html: version.html}
      else
        %{number: number}
      end

    to_history_entry(event, data)
  end

  defp resolve_event(%Event{kind: :state_changed, data: ops} = event, _include_html) do
    to_history_entry(event, %{ops: ops})
  end

  defp resolve_event(
         %Event{kind: :submission_made, data: %{"submission_id" => submission_id}} = event,
         _include_html
       ) do
    submission = Ash.get!(Submission, submission_id, authorize?: false)

    to_history_entry(event, %{
      submission_id: submission.id,
      version: submission.version,
      state: submission.state,
      payload: submission.payload
    })
  end

  defp to_history_entry(event, data) do
    %{
      id: event.id,
      kind: event.kind,
      actor: event_actor_ref(event),
      inserted_at: event.inserted_at,
      data: data
    }
  end

  defp event_actor_ref(event) do
    event = Ash.load!(event, [:user, :agent, :harness], authorize?: false)
    actor = event.user || event.agent
    Actor.ref(actor, %{harness_name: event.harness && event.harness.name})
  end

  # `:map`, not `:struct instance_of: __MODULE__`: `AshAi.Serializer` and
  # `AshJsonApi.Serializer` both render a `:struct` return through the
  # resource's own public attributes, which never includes `__metadata__`
  # — an MCP or HTTP caller would never see the requested Version's html.
  # A plain map's fields are exactly what this action returns.
  defp get_artifact(input, context) do
    artifact_id = input.arguments.artifact_id

    with {:ok, artifact} <- get_owned_artifact(artifact_id, context) do
      number = Map.get(input.arguments, :version) || artifact.current_version

      metadata = %{
        id: artifact.id,
        title: artifact.title,
        organization_id: artifact.organization_id,
        current_version: artifact.current_version,
        archived_at: artifact.archived_at,
        version: number
      }

      if input.arguments.include_html do
        with {:ok, version} <-
               Ash.get(Version, [artifact_id: artifact_id, number: number], authorize?: false) do
          {:ok, Map.put(metadata, :html, version.html)}
        end
      else
        {:ok, metadata}
      end
    end
  end

  # The one MCP tool that both creates an Artifact and publishes a new
  # Version to an existing one (DESIGN.md "Agent interfaces → MCP",
  # `publish_artifact`): `artifact_id` present selects the publish branch,
  # absent selects create. Kept as its own generic action, distinct from
  # the real `create`/`publish` actions each JSON:API route calls
  # directly, so this composition is MCP-only.
  defp publish_artifact(input, context) do
    case Map.get(input.arguments, :artifact_id) do
      nil ->
        params = %{
          title: Map.get(input.arguments, :title),
          html: input.arguments.html,
          organization_id: Map.get(input.arguments, :organization_id)
        }

        __MODULE__
        |> Ash.Changeset.for_create(:create, params, read_opts(context))
        |> Ash.create()

      artifact_id ->
        with {:ok, artifact} <- get_owned_artifact(artifact_id, context) do
          Artifacts.Publishing.publish(
            artifact,
            input.arguments.html,
            Map.get(input.arguments, :if_version),
            read_opts(context)
          )
        end
    end
  end
end
