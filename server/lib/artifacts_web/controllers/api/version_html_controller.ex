defmodule ArtifactsWeb.Api.VersionHtmlController do
  @moduledoc """
  `GET /api/artifacts/:id/versions/:n.html` (DESIGN.md "HTTP API"): the one
  route that returns a Version's stored HTML verbatim, as `text/html`,
  rather than a JSON:API document — `Version` is never its own JSON:API
  resource type (plan §1). Declared in the router ahead of the `/api`
  forward so it wins over `ArtifactsWeb.JsonApiRouter`.

  `Version`'s own read policy already requires membership in the
  Artifact's Organization through the `artifact` relationship, so a
  non-member's request resolves not-found the same way any other read
  does — no separate Artifact fetch is needed first.
  """

  use ArtifactsWeb, :controller

  alias Artifacts.Publishing.Version

  def show(conn, %{"id" => artifact_id, "n" => segment}) do
    actor = Ash.PlugHelpers.get_actor(conn)
    number_text = String.trim_trailing(segment, ".html")

    with {number, ""} <- Integer.parse(number_text),
         {:ok, version} <-
           Ash.get(Version, [artifact_id: artifact_id, number: number], actor: actor) do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, version.html)
    else
      _not_found_or_invalid ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "not found")
    end
  end
end
