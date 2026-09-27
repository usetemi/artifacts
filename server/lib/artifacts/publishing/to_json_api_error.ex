# Every failure `Artifacts.Publishing`'s own actions raise carries its
# stable code (DESIGN.md "Content changes") as a JSON:API error's `code`,
# through the same `Errors.to_code/1` the channel and MCP read (plan §3,
# "Errors"). Without these impls `ash_json_api` logs a warning and falls
# back to a generic 400 "something_went_wrong" for any error it has no
# `AshJsonApi.ToJsonApiError` impl for — confirmed for `Conflict` empirically.
alias Artifacts.Publishing.Errors
alias Artifacts.Publishing.Errors.{Archived, Conflict, NotFound, Quota}

defimpl AshJsonApi.ToJsonApiError, for: Conflict do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 409,
      code: Errors.to_code(error),
      title: "Conflict",
      detail: Exception.message(error)
    }
  end
end

defimpl AshJsonApi.ToJsonApiError, for: Archived do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 409,
      code: Errors.to_code(error),
      title: "Archived",
      detail: Exception.message(error)
    }
  end
end

defimpl AshJsonApi.ToJsonApiError, for: Quota do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 422,
      code: Errors.to_code(error),
      title: "Quota",
      detail: Exception.message(error)
    }
  end
end

defimpl AshJsonApi.ToJsonApiError, for: NotFound do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 404,
      code: Errors.to_code(error),
      title: "NotFound",
      detail: Exception.message(error)
    }
  end
end
