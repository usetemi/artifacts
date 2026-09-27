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
  alias Artifacts.Publishing.{Actor, Event, StateEntry, Submission, Version}
  alias Artifacts.State

  require Ash.Query

  postgres do
    table "artifacts"
    repo Artifacts.Repo

    references do
      reference :organization, on_delete: :restrict
    end
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
      argument :title, :string, allow_nil?: false, constraints: [min_length: 1]
      argument :html, :string, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: true

      change set_attribute(:title, arg(:title))
      change set_attribute(:current_version, 0)
      change ResolveOrganization
      change PublishFirstVersion
    end

    update :publish do
      accept []
      argument :html, :string, allow_nil?: false
      argument :if_version, :integer, allow_nil?: true
      require_atomic? false

      validate HtmlSize

      change Publish
    end

    update :change_state do
      accept []
      argument :ops, {:array, :map}, allow_nil?: false
      require_atomic? false

      change ChangeState
    end

    update :submit do
      accept []
      argument :payload, Artifacts.Type.JSONValue, allow_nil?: true
      require_atomic? false

      change Submit
    end

    read :list do
      argument :organization_id, :uuid, allow_nil?: false
      argument :archived, :boolean, allow_nil?: false, default: false

      filter expr(
               organization_id == ^arg(:organization_id) and
                 ((^arg(:archived) == false and is_nil(archived_at)) or
                    (^arg(:archived) == true and not is_nil(archived_at)))
             )

      prepare build(sort: [updated_at: :desc])
    end

    update :rename do
      accept [:title]
      require_atomic? false
      validate string_length(:title, min: 1)
    end

    update :archive do
      accept []
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
      change set_attribute(:archived_at, nil)
    end

    action :get_state, :map do
      argument :artifact_id, :string, allow_nil?: false

      run fn input, context -> get_state(input, context) end
    end

    action :wait, {:array, :struct} do
      constraints items: [instance_of: Artifacts.Publishing.Submission]
      argument :artifact_id, :string, allow_nil?: false
      argument :since, :integer, allow_nil?: true
      argument :timeout, :integer, allow_nil?: false, default: 45_000
      transaction? false

      run fn input, context -> wait(input, context) end
    end

    action :history, {:array, :map} do
      argument :artifact_id, :string, allow_nil?: false
      argument :after, :integer, allow_nil?: false, default: 0
      argument :limit, :integer, allow_nil?: false, default: 50
      argument :include_html, :boolean, allow_nil?: false, default: false

      run fn input, context -> history(input, context) end
    end

    action :get_artifact, :struct do
      constraints instance_of: Artifacts.Publishing.Artifact
      argument :artifact_id, :string, allow_nil?: false
      argument :version, :integer, allow_nil?: true
      argument :include_html, :boolean, allow_nil?: false, default: false

      run fn input, context -> get_artifact(input, context) end
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

  defp get_state(input, context) do
    artifact_id = input.arguments.artifact_id

    with {:ok, _artifact} <- Ash.get(__MODULE__, artifact_id, read_opts(context)) do
      leaves =
        StateEntry
        |> Ash.Query.filter(artifact_id == ^artifact_id)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.path, &1.value})

      {:ok, State.expand(leaves)}
    end
  end

  defp wait(input, context) do
    artifact_id = input.arguments.artifact_id
    timeout = min(input.arguments.timeout, 50_000)

    with {:ok, _artifact} <- Ash.get(__MODULE__, artifact_id, read_opts(context)) do
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
            _message -> poll_wait(artifact_id, since, deadline)
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
    after_id = input.arguments.after
    limit = min(input.arguments.limit, @max_history_page)

    with {:ok, _artifact} <- Ash.get(__MODULE__, artifact_id, read_opts(context)) do
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

  defp get_artifact(input, context) do
    artifact_id = input.arguments.artifact_id

    with {:ok, artifact} <- Ash.get(__MODULE__, artifact_id, read_opts(context)) do
      number = Map.get(input.arguments, :version) || artifact.current_version
      artifact = Ash.Resource.put_metadata(artifact, :version, number)

      if input.arguments.include_html do
        version = Ash.get!(Version, [artifact_id: artifact_id, number: number], authorize?: false)
        {:ok, Ash.Resource.put_metadata(artifact, :html, version.html)}
      else
        {:ok, artifact}
      end
    end
  end
end
