defmodule ArtifactsWeb.Plugs.HostRoleTest do
  use ExUnit.Case, async: true

  alias ArtifactsWeb.Plugs.HostRole

  # Matches config/test.exs.
  @app_host "localhost"
  @content_host "127.0.0.1"

  defp conn_for_host(host) do
    Plug.Test.conn(:get, "http://#{host}/")
  end

  test "assigns :app for the configured app host" do
    conn = @app_host |> conn_for_host() |> HostRole.call(HostRole.init([]))
    assert conn.assigns.host_role == :app
  end

  test "assigns :content for the configured content host" do
    conn = @content_host |> conn_for_host() |> HostRole.call(HostRole.init([]))
    assert conn.assigns.host_role == :content
  end

  test "assigns nil for an unrecognized host" do
    conn = "evil.example.com" |> conn_for_host() |> HostRole.call(HostRole.init([]))
    assert conn.assigns.host_role == nil
  end
end
