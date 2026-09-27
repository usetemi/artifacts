defmodule Artifacts.Publishing do
  @moduledoc """
  Artifacts, Versions, State, Submissions, and the History (DOMAIN.md §1.2,
  §1.3): one live page with a stable identity and URL, per Organization.

  Every code interface below whose action creates the aggregate
  (`create_artifact`) or updates it (`publish`, `change_state`, `submit`,
  `rename`, `archive`, `unarchive`) takes the record itself except
  `create_artifact`, which has none yet. The four generic-action interfaces
  (`get_state`, `wait`, `history`, `get_artifact`) take the Artifact's id,
  not the record — a generic action has no record subject (plan §3).
  """

  use Ash.Domain, otp_app: :artifacts, extensions: [AshAi, AshJsonApi.Domain]

  alias Artifacts.Publishing.Artifact

  resources do
    resource Artifacts.Publishing.Artifact do
      define :create_artifact, action: :create, args: [:title, :html]
      define :publish, action: :publish, args: [:html, :if_version]
      define :change_state, action: :change_state, args: [:ops]
      define :submit, action: :submit, args: [:payload]
      define :rename, action: :rename, args: [:title]
      define :archive, action: :archive
      define :unarchive, action: :unarchive
      define :list_artifacts, action: :list, args: [:organization_id]

      define :get_state, action: :get_state, args: [:artifact_id]
      define :wait, action: :wait, args: [:artifact_id]
      define :history, action: :history, args: [:artifact_id]
      define :get_artifact, action: :get_artifact, args: [:artifact_id]
      define :publish_artifact, action: :publish_artifact, args: [:html]
    end

    resource Artifacts.Publishing.Version
    resource Artifacts.Publishing.StateEntry
    resource Artifacts.Publishing.Submission
    resource Artifacts.Publishing.Event
  end

  # DESIGN.md "Agent interfaces → MCP": the tool names are exactly the
  # table's, mapped onto the Artifact actions above (plan §3, "Domain code
  # interfaces"). `list_artifacts`/`change_state`/`submit`/`rename_artifact`/
  # `archive_artifact`/`unarchive_artifact` are the resource's own CRUD
  # actions; `get_state`/`wait`/`history`/`get_artifact`/`publish_artifact`
  # are generic actions ash_ai dispatches the same way.
  tools do
    tool :list_artifacts, Artifact, :list
    tool :get_artifact, Artifact, :get_artifact
    tool :publish_artifact, Artifact, :publish_artifact
    tool :get_state, Artifact, :get_state
    tool :change_state, Artifact, :change_state
    tool :submit, Artifact, :submit
    tool :wait, Artifact, :wait
    tool :history, Artifact, :history
    tool :rename_artifact, Artifact, :rename
    tool :archive_artifact, Artifact, :archive
    tool :unarchive_artifact, Artifact, :unarchive
  end

  # DESIGN.md "Agent interfaces → HTTP API": the same Artifact actions,
  # reached under `/api/artifacts`. `Version` is never its own JSON:API
  # resource type (plan §1); its HTML is reached only through the raw
  # `versions/:n.html` route declared in the router ahead of the `/api`
  # forward, and through `get_artifact`'s own `include_html` argument.
  json_api do
    routes do
      base_route "/artifacts", Artifact do
        get :read
        index :list
        post :create
        patch :publish, route: "/:id/publish"
        patch :change_state, route: "/:id/state"
        patch :submit, route: "/:id/submit"
        patch :rename, route: "/:id/rename"
        patch :archive, route: "/:id/archive"
        patch :unarchive, route: "/:id/unarchive"
        route :get, "/:artifact_id/state", :get_state
        route :post, "/:artifact_id/wait", :wait
        route :get, "/:artifact_id/history", :history
      end
    end
  end
end
