defmodule Artifacts.Publishing.Artifact.Changes.Publish do
  @moduledoc """
  The whole of `publish` (DESIGN.md "Content changes"): locks the Artifact
  row (`LockRow`, which also refuses an archived Artifact against that fresh
  read), compares `if_version` against the locked `current_version`, and
  bumps it — all inside one `before_action` hook, so the compare always
  reads the just-locked row rather than a value read before the lock. Then,
  once the update commits, inserts the new `Version` row and its
  `version_published` `Event` in the same transaction.
  """

  use Ash.Resource.Change

  alias Artifacts.Publishing.Artifact.Changes.{LockRow, RecordEvent}
  alias Artifacts.Publishing.{Actor, Errors.Conflict, Version}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&lock_and_compare/1)
    |> Ash.Changeset.after_action(fn changeset, artifact ->
      insert_version(changeset, artifact, context)
    end)
  end

  defp lock_and_compare(changeset) do
    changeset = LockRow.lock_and_refresh(changeset)

    if changeset.valid? do
      compare_and_bump(changeset)
    else
      changeset
    end
  end

  defp compare_and_bump(changeset) do
    if_version = Ash.Changeset.get_argument(changeset, :if_version)
    locked = changeset.data

    if if_version && if_version != locked.current_version do
      Ash.Changeset.add_error(changeset, Conflict.exception(artifact_id: locked.id))
    else
      Ash.Changeset.force_change_attribute(
        changeset,
        :current_version,
        locked.current_version + 1
      )
    end
  end

  defp insert_version(changeset, artifact, context) do
    html = Ash.Changeset.get_argument(changeset, :html)
    shared = changeset.context[:shared] || %{}

    attrs =
      Map.merge(
        %{artifact_id: artifact.id, number: artifact.current_version, html: html},
        Actor.columns(context.actor, shared)
      )

    case Ash.create(Version, attrs,
           actor: context.actor,
           authorize?: false,
           context: %{shared: shared}
         ) do
      {:ok, _version} ->
        RecordEvent.record(
          artifact,
          :version_published,
          %{"number" => artifact.current_version},
          context.actor,
          shared
        )

      {:error, error} ->
        {:error, error}
    end
  end
end
