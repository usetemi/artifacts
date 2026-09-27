defmodule Artifacts.Publishing.Artifact.Changes.PublishFirstVersion do
  @moduledoc """
  `create` is `publish` on a new Artifact (DESIGN.md "Content changes"):
  once the Artifact row (`current_version` 0) is inserted, this calls the
  `publish` update action on it to insert Version 1 and its Event, inside
  the same transaction — a failure here rolls the whole `create` back too.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, artifact ->
      html = Ash.Changeset.get_argument(changeset, :html)
      shared = changeset.context[:shared] || %{}

      artifact
      |> Ash.Changeset.for_update(:publish, %{html: html},
        actor: context.actor,
        authorize?: false,
        context: %{shared: shared}
      )
      |> Ash.update()
    end)
  end
end
