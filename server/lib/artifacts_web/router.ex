defmodule ArtifactsWeb.Router do
  use ArtifactsWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug ArtifactsWeb.Plugs.RequireHost, :app
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArtifactsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  # A published page is a plain document on the content host: no session,
  # no CSRF token, no root layout. Slice B's page controller sets its own
  # CSP.
  pipeline :content do
    plug ArtifactsWeb.Plugs.RequireHost, :content
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug ArtifactsWeb.Plugs.RequireHost, :app
    plug ArtifactsWeb.Plugs.BearerAuth
    # No `:accepts` here: AshJsonApi.Router negotiates its own content type
    # (application/vnd.api+json is not a registered Phoenix format), and
    # the raw-HTML-by-version route needs text/html through this same
    # pipeline.
  end

  pipeline :mcp do
    plug ArtifactsWeb.Plugs.RequireHost, :app
    plug ArtifactsWeb.Plugs.BearerAuth
  end

  scope "/", ArtifactsWeb do
    pipe_through :browser

    ash_authentication_live_session :artifacts,
      on_mount: [{ArtifactsWeb.LiveUserAuth, :live_user_required}] do
      live "/", ArtifactsLive
      live "/a/:id", ArtifactLive
      live "/settings", SettingsLive
    end

    sign_in_route(
      resources: [Artifacts.Accounts.User],
      overrides: [ArtifactsWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default],
      on_mount: [{ArtifactsWeb.LiveUserAuth, :live_no_user}],
      auth_routes_prefix: "/auth"
    )

    sign_out_route(AuthController)

    # Declared last: it forwards the whole "/auth" path to
    # AshAuthentication.Phoenix.StrategyRouter, which would otherwise shadow
    # any later route also prefixed "/auth" (none exist here, but this is
    # the safe, documented order — notes/ash_authentication.md §5.1).
    auth_routes(AuthController, Artifacts.Accounts.User)
  end

  scope "/", ArtifactsWeb do
    pipe_through :content
    # Slice B fills: `get "/a/:id/page", PageController, :page`.
  end

  scope "/api", ArtifactsWeb do
    pipe_through :api
    # Slice C fills: the raw-HTML-by-version route (declared before the
    # forward below), then `forward "/", ArtifactsWeb.JsonApiRouter`.
  end

  scope "/mcp" do
    pipe_through :mcp
    # Slice C fills: `forward "/", AshAi.Mcp.Router, tools: [...],
    # otp_app: :artifacts, mcp_name: "Artifacts MCP Server"`.
  end
end
