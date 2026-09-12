defmodule ArtifactsWeb.Router do
  use ArtifactsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArtifactsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # A published page is a plain document: no session, no CSRF token, no
  # root layout. The controller sets the CSP for it.
  pipeline :page do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArtifactsWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/a/:id", ArtifactLive
  end

  scope "/", ArtifactsWeb do
    pipe_through :page

    get "/a/:id/page", PageController, :page
  end

  scope "/api", ArtifactsWeb.API do
    pipe_through :api

    get "/artifacts", ArtifactController, :index
    post "/artifacts", ArtifactController, :create
    get "/artifacts/:id", ArtifactController, :show
    put "/artifacts/:id", ArtifactController, :update
    post "/artifacts/:id/archive", ArtifactController, :archive
    get "/artifacts/:id/history", HistoryController, :index
    get "/artifacts/:id/versions", ArtifactController, :versions
    get "/artifacts/:id/versions/:number", ArtifactController, :version
    get "/artifacts/:id/state", StateController, :show
    post "/artifacts/:id/state", StateController, :update
    get "/artifacts/:id/submissions", SubmissionController, :index
    post "/artifacts/:id/submissions", SubmissionController, :create
  end
end
