defmodule ArtifactsWeb.JsonApiRouter do
  @moduledoc """
  The HTTP API (DESIGN.md "Agent interfaces → HTTP API"): "the same actions"
  MCP exposes, routed per each domain's own `json_api do routes do ... end
  end` — `Artifacts.Publishing`'s Artifact actions, and
  `Artifacts.Accounts`' one MCP tool, `list_organizations`. Mounted at
  `/api` in the router's `:api` scope, behind `ArtifactsWeb.Plugs.BearerAuth`
  — `AshJsonApi.Request` reads the actor and context `BearerAuth` already
  put on the `conn` via `Ash.PlugHelpers`, the same way MCP does.
  """

  use AshJsonApi.Router,
    domains: [Artifacts.Accounts, Artifacts.Publishing],
    prefix: "/api"
end
