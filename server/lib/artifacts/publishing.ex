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

  use Ash.Domain, otp_app: :artifacts

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
    end

    resource Artifacts.Publishing.Version
    resource Artifacts.Publishing.StateEntry
    resource Artifacts.Publishing.Submission
    resource Artifacts.Publishing.Event
  end
end
