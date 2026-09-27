defmodule Artifacts.Publishing.Errors.Quota do
  @moduledoc """
  Raised when a per-Artifact cap is reached: 10,000 state rows or 10,000
  Submissions (DESIGN.md "Content changes", "Caps").
  """

  use Splode.Error, fields: [:artifact_id, :limit], class: :invalid

  @impl true
  def message(error), do: "quota of #{error.limit} reached"
end
