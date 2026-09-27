defmodule ArtifactsWeb.Plugs.HostRole do
  @moduledoc """
  Assigns `conn.assigns.host_role` (`:app` or `:content`) by comparing the
  request host against the configured `:app_host`/`:content_host`.

  `scope ..., host:` is a compile-time Phoenix router argument and cannot
  vary per deployment from the same built release, so the app-host /
  content-host split is a runtime plug instead: this one assigns the role,
  and `ArtifactsWeb.Plugs.RequireHost` (mounted per router pipeline) 404s on
  a mismatch.

  Mounted once, early, in `ArtifactsWeb.Endpoint`.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    app_host = Application.fetch_env!(:artifacts, :app_host)
    content_host = Application.fetch_env!(:artifacts, :content_host)

    role =
      cond do
        conn.host == app_host -> :app
        conn.host == content_host -> :content
        true -> nil
      end

    assign(conn, :host_role, role)
  end
end
