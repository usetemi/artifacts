defmodule Artifacts.Publishing.Errors.Archived do
  @moduledoc """
  Raised by a content action (`publish`, `change_state`, `submit`) on an
  archived Artifact (DESIGN.md "Content changes": "Every content action
  validates `archived_at` is nil and fails with an `archived` error
  otherwise").
  """

  use Splode.Error, fields: [:artifact_id], class: :invalid

  @impl true
  def message(_error), do: "the Artifact is archived"
end
