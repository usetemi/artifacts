defmodule Artifacts.Publishing.Artifact.Changes.ChangeState do
  @moduledoc """
  The whole of `change_state` (DESIGN.md "Content changes" and "State"):
  locks the Artifact row (`LockRow`, which also refuses an archived Artifact
  against that fresh read), normalizes the ops with
  `Artifacts.State.normalize_ops/1` (the path validations and the top-level
  null-to-delete normalization, shared with the browser runtime), applies
  each op's leaf writes and deletes, enforces the 10,000-row cap, and
  records exactly one `state_changed` `Event` for the whole batch — all
  inside the update's own transaction, so a rollback (an invalid op, the row
  cap) undoes every write.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Artifacts.Publishing.Artifact.Changes.{LockRow, RecordEvent}
  alias Artifacts.Publishing.{Actor, Errors.Quota, StateEntry}
  alias Artifacts.State

  @max_state_rows 10_000

  @impl true
  def change(changeset, _opts, context) do
    raw_ops = Ash.Changeset.get_argument(changeset, :ops)

    changeset = Ash.Changeset.before_action(changeset, &LockRow.lock_and_refresh/1)

    case State.normalize_ops(raw_ops) do
      {:ok, []} ->
        Ash.Changeset.add_error(changeset, field: :ops, message: "must not be empty")

      {:ok, ops} ->
        Ash.Changeset.after_action(changeset, fn changeset, artifact ->
          apply_ops(changeset, artifact, ops, context)
        end)

      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :ops, message: reason)
    end
  end

  defp apply_ops(changeset, artifact, ops, context) do
    shared = changeset.context[:shared] || %{}
    actor_cols = Actor.columns(context.actor, shared)
    now = DateTime.utc_now()
    ops_json = Enum.map(ops, &op_json/1)

    with :ok <- write_ops(artifact.id, ops, actor_cols, now),
         :ok <- check_quota(artifact.id) do
      artifact
      |> Ash.Resource.put_metadata(:ops, ops_json)
      |> RecordEvent.record(:state_changed, ops_json, context.actor, shared)
    end
  end

  defp write_ops(artifact_id, ops, actor_cols, now) do
    Enum.reduce_while(ops, :ok, fn op, :ok ->
      case write_op(artifact_id, op, actor_cols, now) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp write_op(artifact_id, %{op: :delete, path: path}, _actor_cols, _now) do
    delete_subtree(artifact_id, path)
  end

  defp write_op(artifact_id, %{op: :set, path: path, value: value}, actor_cols, now) do
    with :ok <- delete_subtree(artifact_id, path),
         :ok <- delete_ancestors(artifact_id, path) do
      write_leaves(artifact_id, path, value, actor_cols, now)
    end
  end

  defp write_leaves(artifact_id, path, value, actor_cols, now) do
    leaves = State.flatten(path, value)

    if map_size(leaves) == 0 do
      :ok
    else
      inputs =
        Enum.map(leaves, fn {leaf_path, leaf_value} ->
          Map.merge(
            %{artifact_id: artifact_id, path: leaf_path, value: leaf_value, updated_at: now},
            actor_cols
          )
        end)

      bulk_result(
        Ash.bulk_create(inputs, StateEntry, :upsert,
          authorize?: false,
          return_errors?: true,
          stop_on_error?: true
        )
      )
    end
  end

  defp delete_subtree(artifact_id, path) do
    prefix = path <> "."
    prefix_len = byte_size(prefix)

    StateEntry
    |> Ash.Query.filter(
      artifact_id == ^artifact_id and
        (path == ^path or fragment("left(?, ?) = ?", path, ^prefix_len, ^prefix))
    )
    |> destroy_matching()
  end

  defp delete_ancestors(artifact_id, path) do
    case State.ancestors(path) do
      [] ->
        :ok

      ancestors ->
        StateEntry
        |> Ash.Query.filter(artifact_id == ^artifact_id and path in ^ancestors)
        |> destroy_matching()
    end
  end

  defp destroy_matching(query) do
    bulk_result(
      Ash.bulk_destroy(query, :destroy, %{},
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )
    )
  end

  defp bulk_result(%Ash.BulkResult{status: status}) when status in [:success, :partial_success],
    do: :ok

  defp bulk_result(%Ash.BulkResult{errors: errors}), do: {:error, errors}

  defp check_quota(artifact_id) do
    count =
      StateEntry
      |> Ash.Query.filter(artifact_id == ^artifact_id)
      |> Ash.count!(authorize?: false)

    if count > @max_state_rows do
      {:error, Quota.exception(artifact_id: artifact_id, limit: @max_state_rows)}
    else
      :ok
    end
  end

  defp op_json(%{op: :set, path: path, value: value}),
    do: %{"op" => "set", "path" => path, "value" => value}

  defp op_json(%{op: :delete, path: path}), do: %{"op" => "delete", "path" => path}
end
