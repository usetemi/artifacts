defmodule Artifacts.Publishing.Artifact.Changes.LockRow do
  @moduledoc """
  Locks the Artifact row inside the update's own transaction and swaps the
  changeset's `data` for that fresh read, then refuses an archived Artifact
  against it (DESIGN.md "Content changes": archived refusal on every content
  action).

  `changeset.data` is whatever struct the caller happened to pass in, which
  may be stale (fetched before a concurrent `archive`, `publish`, or
  `change_state` on the same Artifact). Checking `archived_at` or
  `current_version` against that stale struct would let a caller holding an
  old handle bypass the archived refusal or record the wrong version. Every
  content action (`publish`, `change_state`, `submit`) calls this first, so
  every downstream read of `changeset.data` — the archived check, the
  version comparison, the version a Submission records — sees the row as it
  actually is right now.
  """

  alias Artifacts.Publishing.Errors.Archived

  @spec lock_and_refresh(Ash.Changeset.t()) :: Ash.Changeset.t()
  def lock_and_refresh(changeset) do
    primary_key = Ash.Resource.Info.primary_key(changeset.resource)
    pkey = changeset.data |> Map.take(primary_key) |> Map.to_list()

    case Ash.get(changeset.resource, pkey,
           domain: changeset.domain,
           actor: nil,
           authorize?: false,
           lock: :for_update
         ) do
      {:ok, %{archived_at: nil} = locked} ->
        Map.put(changeset, :data, locked)

      {:ok, locked} ->
        Ash.Changeset.add_error(changeset, Archived.exception(artifact_id: locked.id))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
