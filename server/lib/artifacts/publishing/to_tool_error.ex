# Every failure `Artifacts.Publishing`'s own actions raise carries its
# stable code (DESIGN.md "Content changes") as an MCP tool's error text,
# through the same `Errors.to_code/1` the channel and the HTTP API read
# (plan §3, "Errors"). `ash_ai` already implements `AshAi.ToToolError` for
# every `Ash.Error.*` struct it knows about — most notably
# `Ash.Error.Forbidden.Policy` -> `"forbidden"`, which already matches our
# code — so these impls cover only the errors this app defines itself,
# never redefining one of `ash_ai`'s own impls (which would be a module
# redefinition and fail `--warnings-as-errors`).
alias Artifacts.Publishing.Errors
alias Artifacts.Publishing.Errors.{Archived, Conflict, NotFound, Quota}

defimpl AshAi.ToToolError, for: Conflict do
  def to_tool_error(error), do: Errors.to_code(error)
end

defimpl AshAi.ToToolError, for: Archived do
  def to_tool_error(error), do: Errors.to_code(error)
end

defimpl AshAi.ToToolError, for: Quota do
  def to_tool_error(error), do: Errors.to_code(error)
end

defimpl AshAi.ToToolError, for: NotFound do
  def to_tool_error(error), do: Errors.to_code(error)
end
