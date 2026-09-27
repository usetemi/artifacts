defmodule Artifacts.Publishing.Errors.NotFound do
  @moduledoc """
  Raised by a generic action's own record lookup (`get_state`, `wait`,
  `history`, `get_artifact`, `publish_artifact`) in place of Ash's own
  `Ash.Error.Query.NotFound`, so an MCP tool call's error text is the
  stable "not_found" code (`Errors.to_code/1`) rather than `ash_ai`'s own
  built-in `AshAi.ToToolError` text for `Ash.Error.Query.NotFound`
  ("could not be found") — a struct this app cannot safely re-implement
  the protocol for without redefining a module `ash_ai` already defines.
  """

  use Splode.Error, fields: [:artifact_id], class: :invalid

  @impl true
  def message(_error), do: "could not be found"
end
