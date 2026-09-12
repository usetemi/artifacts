defmodule ArtifactsWeb.PageController do
  use ArtifactsWeb, :controller

  alias Artifacts.Store

  # Scripts and fonts may come from the few CDNs an agent is likely to
  # reach for; everything a page talks to (sockets, fetches) stays on
  # this origin. Images are open because pages embed charts and photos
  # from anywhere and there is nothing to exfiltrate through them.
  @csp Enum.join(
         [
           "default-src 'self'",
           "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com https://esm.sh",
           "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com",
           "font-src 'self' data: https://fonts.gstatic.com",
           "img-src * data: blob:",
           "media-src * data: blob:",
           "connect-src 'self'",
           "frame-ancestors 'self'"
         ],
         "; "
       )

  def home(conn, _params) do
    text(conn, "artifacts host\n")
  end

  @doc """
  Serves the current version exactly as published, with the runtime
  script injected at serve time so the stored HTML never depends on the
  host. A page without a `<head>` gets the script before everything else.
  """
  def page(conn, %{"id" => id}) do
    with {:ok, artifact} <- Store.get_open(id),
         {:ok, version} <- Store.get_version(id, artifact.current_version) do
      conn
      |> put_resp_header("content-security-policy", @csp)
      |> put_resp_header("cache-control", "no-store")
      |> html(inject_runtime(version.html, id, version.number))
    else
      {:error, _missing_or_archived} ->
        conn |> put_status(:not_found) |> text("not found\n")
    end
  end

  @doc false
  def inject_runtime(html, id, version) do
    tag =
      ~s(<script src="#{~p"/assets/js/runtime.js"}" data-artifact-id="#{id}" data-version="#{version}"></script>)

    case Regex.run(~r/<head[^>]*>/i, html, return: :index) do
      [{start, length}] ->
        {before, rest} = String.split_at(html, start + length)
        before <> tag <> rest

      nil ->
        tag <> html
    end
  end
end
