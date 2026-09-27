defmodule ArtifactsWeb.RouterTest do
  use ArtifactsWeb.ConnCase, async: true

  describe "Google auth routes" do
    test "the callback route is /auth/user/google/callback", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> get("/auth/user/google/callback")

      # No prior request-phase session exists, so AshAuthentication's OAuth2
      # plug fails cleanly and reaches ArtifactsWeb.AuthController.failure/3,
      # which redirects to /sign-in. A generic Phoenix "no route matched" 404
      # would prove the opposite: that this path is not wired up.
      assert redirected_to(conn) == "/sign-in"
    end

    test "the callback route 404s on the content host", %{conn: conn} do
      conn = Map.put(conn, :host, "127.0.0.1")

      assert_error_sent 404, fn ->
        get(conn, "/auth/user/google/callback")
      end
    end
  end
end
