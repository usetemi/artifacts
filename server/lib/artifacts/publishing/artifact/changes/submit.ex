defmodule Artifacts.Publishing.Artifact.Changes.Submit do
  @moduledoc """
  The whole of `submit` (DESIGN.md "Content changes"): locks the Artifact
  row (`LockRow`, which also refuses an archived Artifact against that fresh
  read, and gives the Submission the Artifact's true current Version rather
  than whatever the caller's struct happened to say), snapshots the current
  State, records a `Submission` (bounded to 10,000 per Artifact), and its
  `submission_made` `Event`, all inside the update's own transaction.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Artifacts.Publishing.Artifact.Changes.{LockRow, RecordEvent}
  alias Artifacts.Publishing.{Actor, Errors.Quota, StateEntry, Submission}
  alias Artifacts.State

  @max_submissions 10_000

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&LockRow.lock_and_refresh/1)
    |> Ash.Changeset.after_action(fn changeset, artifact ->
      do_submit(changeset, artifact, context)
    end)
  end

  defp do_submit(changeset, artifact, context) do
    with :ok <- check_quota(artifact.id) do
      shared = changeset.context[:shared] || %{}
      payload = Ash.Changeset.get_argument(changeset, :payload)

      attrs =
        Map.merge(
          %{
            artifact_id: artifact.id,
            version: artifact.current_version,
            state: current_state(artifact.id),
            payload: payload
          },
          Actor.columns(context.actor, shared)
        )

      case Ash.create(Submission, attrs,
             actor: context.actor,
             authorize?: false,
             context: %{shared: shared}
           ) do
        {:ok, submission} ->
          artifact
          |> Ash.Resource.put_metadata(:submission_id, submission.id)
          |> RecordEvent.record(
            :submission_made,
            %{"submission_id" => submission.id},
            context.actor,
            shared
          )

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp current_state(artifact_id) do
    StateEntry
    |> Ash.Query.filter(artifact_id == ^artifact_id)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.path, &1.value})
    |> State.expand()
  end

  defp check_quota(artifact_id) do
    count =
      Submission
      |> Ash.Query.filter(artifact_id == ^artifact_id)
      |> Ash.count!(authorize?: false)

    if count >= @max_submissions do
      {:error, Quota.exception(artifact_id: artifact_id, limit: @max_submissions)}
    else
      :ok
    end
  end
end
