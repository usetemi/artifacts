defmodule ArtifactsWeb.Origins do
  @moduledoc """
  The app origin, the content origin, and the content host's socket URL
  (DESIGN.md "Page origin and runtime"), all derived from the endpoint's
  own configured scheme and port rather than the request's — so they stay
  correct behind a TLS-terminating proxy, where `conn.scheme`/`conn.port`
  reflect the internal listener, not what the browser actually used.

  Used by `ArtifactsWeb.PageController` (the `window.__ARTIFACT__` payload
  and the CSP) and `ArtifactsWeb.ArtifactSocket` (`check_origin`).
  """

  @spec app_origin() :: String.t()
  def app_origin, do: origin(Application.fetch_env!(:artifacts, :app_host))

  @spec content_origin() :: String.t()
  def content_origin, do: origin(Application.fetch_env!(:artifacts, :content_host))

  @doc "The full `ws(s)://` URL of the content host's page socket, path included."
  @spec socket_url() :: String.t()
  def socket_url do
    uri = ArtifactsWeb.Endpoint.struct_url()
    ws_scheme = if uri.scheme == "https", do: "wss", else: "ws"

    %{
      uri
      | scheme: ws_scheme,
        host: Application.fetch_env!(:artifacts, :content_host),
        path: "/socket"
    }
    |> URI.to_string()
  end

  defp origin(host) do
    ArtifactsWeb.Endpoint.struct_url()
    |> Map.put(:host, host)
    |> URI.to_string()
  end
end
