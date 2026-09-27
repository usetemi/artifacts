defmodule ArtifactsWeb.PageController do
  @moduledoc """
  Serves an Artifact's current Version on the content host (DESIGN.md
  "Page origin and runtime"): verifies the page token, then injects
  `window.__ARTIFACT__` and the runtime script right after `<head>`.
  Stored HTML is never modified.

  The router declares this route with `log: false`, so the token in `t`
  never reaches the "Processing with..." request log Phoenix would
  otherwise emit at the route's default level.
  """

  use ArtifactsWeb, :controller

  alias Artifacts.Publishing.Version
  alias ArtifactsWeb.{Origins, PageToken}

  # Scripts and fonts may come from the few CDNs an agent is likely to
  # reach for; everything a page talks to (sockets, fetches) stays on
  # this origin. Images are open because pages embed charts and photos
  # from anywhere and there is nothing to exfiltrate through them.
  # `connect-src` and `frame-ancestors` are filled in per request from
  # `ArtifactsWeb.Origins`, since the content and app hosts are
  # runtime-configured, not compile-time constants.
  @csp_parts [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com https://esm.sh",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    "img-src * data: blob:",
    "media-src * data: blob:"
  ]

  @doc """
  Verifies the page token and serves the current Version's HTML. An
  invalid or expired token, one minted for a different artifact than `id`
  names, or one whose artifact is archived, is refused the same way:
  `ArtifactsWeb.NotFoundError` (404), never revealing which it was.
  """
  def page(conn, %{"id" => id, "t" => token}) do
    with {:ok, %{artifact: %{id: ^id, archived_at: nil} = artifact, user: user}} <-
           PageToken.verify(token),
         {:ok, version} <-
           Ash.get(Version, [artifact_id: id, number: artifact.current_version], actor: user) do
      conn
      |> put_resp_header("content-security-policy", csp())
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("cache-control", "no-store")
      |> html(inject_runtime(version.html, artifact, token, user))
    else
      _invalid_expired_wrong_artifact_or_missing_version ->
        raise ArtifactsWeb.NotFoundError
    end
  end

  def page(_conn, _params), do: raise(ArtifactsWeb.NotFoundError)

  @doc false
  def inject_runtime(html, artifact, token, user) do
    payload = %{
      id: artifact.id,
      version: artifact.current_version,
      token: token,
      socketUrl: Origins.socket_url(),
      appOrigin: Origins.app_origin(),
      viewer: %{id: user.id, name: user.name}
    }

    json = payload |> Jason.encode!() |> String.replace("</", "<\\/")

    tag =
      ~s(<script>window.__ARTIFACT__ = #{json}</script>) <>
        ~s(<script src="#{Origins.content_origin()}#{~p"/assets/js/runtime.js"}"></script>)

    case Regex.run(~r/<head[^>]*>/i, html, return: :index) do
      [{start, length}] ->
        {before, rest} = String.split_at(html, start + length)
        before <> tag <> rest

      nil ->
        tag <> html
    end
  end

  defp csp do
    socket_origin = String.replace(Origins.content_origin(), ~r/^http/, "ws")

    Enum.join(
      @csp_parts ++
        [
          "connect-src 'self' #{socket_origin}",
          "frame-ancestors #{Origins.app_origin()}"
        ],
      "; "
    )
  end
end
