defmodule Artifacts.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ArtifactsWeb.Telemetry,
      Artifacts.Repo,
      {DNSCluster, query: Application.get_env(:artifacts, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Artifacts.PubSub},
      ArtifactsWeb.Presence,
      ArtifactsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Artifacts.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArtifactsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
