defmodule ArtifactsWeb.Plugs.RequireHostTest do
  use ExUnit.Case, async: true

  alias ArtifactsWeb.Plugs.RequireHost

  defp conn_with_role(role) do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Conn.assign(:host_role, role)
  end

  test "passes the conn through when the role matches" do
    conn = RequireHost.call(conn_with_role(:app), RequireHost.init(:app))
    refute conn.halted
  end

  test "raises ArtifactsWeb.NotFoundError when the role doesn't match" do
    assert_raise ArtifactsWeb.NotFoundError, fn ->
      RequireHost.call(conn_with_role(:content), RequireHost.init(:app))
    end
  end

  test "raises ArtifactsWeb.NotFoundError when no role was assigned" do
    assert_raise ArtifactsWeb.NotFoundError, fn ->
      RequireHost.call(Plug.Test.conn(:get, "/"), RequireHost.init(:app))
    end
  end
end
