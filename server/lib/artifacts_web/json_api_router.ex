defmodule ArtifactsWeb.JsonApiRouter do
  @moduledoc """
  The HTTP API (DESIGN.md "Agent interfaces → HTTP API"): the same
  `Artifacts.Publishing` actions MCP exposes, routed per that domain's own
  `json_api do routes do ... end end`. Mounted at `/api` in the router's
  `:api` scope, behind `ArtifactsWeb.Plugs.BearerAuth` — `AshJsonApi.Request`
  reads the actor and context `BearerAuth` already put on the `conn` via
  `Ash.PlugHelpers`, the same way MCP does.
  """

  use AshJsonApi.Router,
    domains: [Artifacts.Publishing],
    prefix: "/api"
end
