defmodule Artifacts.Publishing.Errors.Conflict do
  @moduledoc """
  Raised by `Artifact.publish` when `if_version` no longer matches the
  Artifact's current Version at the moment of the row lock (DESIGN.md
  "Content changes"): another Version was published first.
  """

  use Splode.Error, fields: [:artifact_id], class: :invalid

  @impl true
  def message(_error), do: "another Version was published first"
end
