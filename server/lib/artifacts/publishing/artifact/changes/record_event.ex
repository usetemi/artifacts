defmodule Artifacts.Publishing.Artifact.Changes.RecordEvent do
  @moduledoc """
  Shared by `Publish`, `ChangeState`, and `Submit`: inserts the one `Event`
  each of them writes, with `authorize?: false` since the parent
  `Artifact` action already established the actor may act on this
  Artifact (DESIGN.md "Content changes").
  """

  alias Artifacts.Publishing.{Actor, Event}

  @spec record(Ash.Resource.record(), atom(), term(), term(), Actor.shared()) ::
          {:ok, Ash.Resource.record()} | {:error, Ash.Error.t()}
  def record(artifact, kind, data, actor, shared) do
    attrs =
      Map.merge(
        %{artifact_id: artifact.id, kind: kind, data: data},
        Actor.columns(actor, shared)
      )

    case Ash.create(Event, attrs, actor: actor, authorize?: false, context: %{shared: shared}) do
      {:ok, _event} -> {:ok, artifact}
      {:error, error} -> {:error, error}
    end
  end
end
