defmodule ArtifactsWeb.Router do
  use ArtifactsWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug ArtifactsWeb.Plugs.RequireHost, :app
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
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

    auth_routes(AuthController, Artifacts.Accounts.User)
    # Slice D fills: the Artifacts/Settings LiveViews, sign_in_route,
    # sign_out_route.
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
