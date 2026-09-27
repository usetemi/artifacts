defmodule ArtifactsWeb.Plugs.RequireHost do
  @moduledoc """
  Raises `ArtifactsWeb.NotFoundError` (404) unless `conn.assigns.host_role`,
  set by `ArtifactsWeb.Plugs.HostRole`, matches the role this pipeline
  requires (`:app` or `:content`).

  Used as a per-pipeline plug argument in `ArtifactsWeb.Router`: the
  `:browser`, `:api`, and `:mcp` pipelines require `:app`; the `:content`
  pipeline requires `:content`.
  """

  @behaviour Plug

  @impl true
  def init(expected_role) when expected_role in [:app, :content], do: expected_role

  @impl true
  def call(%{assigns: %{host_role: expected_role}} = conn, expected_role), do: conn

  def call(_conn, _expected_role) do
    raise ArtifactsWeb.NotFoundError
  end
end
