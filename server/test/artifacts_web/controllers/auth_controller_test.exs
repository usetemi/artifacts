defmodule ArtifactsWeb.AuthControllerTest do
  use ArtifactsWeb.ConnCase, async: false

  import Artifacts.AccountsFixtures

  alias Artifacts.Accounts.User
  alias ArtifactsWeb.AuthController

  require Ash.Query

  # Per plan and repo convention (see test/artifacts_web/router_test.exs):
  # simulate the OAuth callback through the strategy's own action or the
  # controller's success/failure callbacks, never by calling Google.

  test "the sign-in page renders the Google link at the configured auth prefix", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200)

    assert html =~ "Sign in with Google"
    assert html =~ "auth-page"
    assert html =~ ~s(href="/auth/user/google")
  end

  test "success stores the token in the session and redirects home", %{conn: conn} do
    user = user_fixture!()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> AuthController.success({:google, :register}, user, user.__metadata__.token)

    assert redirected_to(conn) == "/"
    assert get_session(conn, "user_token") == user.__metadata__.token
  end

  test "a rejected sign-up flashes a message naming the allowed domains and writes no User",
       %{conn: conn} do
    Application.put_env(:artifacts, :signup_email_domains, "usetemi.com")

    try do
      email = "someone@not-usetemi.example"

      strategy = AshAuthentication.Info.strategy!(User, :google)

      assert {:error, error} =
               AshAuthentication.Strategy.action(strategy, :register, %{
                 "user_info" => %{
                   "sub" => "s-#{System.unique_integer([:positive])}",
                   "email" => email,
                   "email_verified" => true,
                   "name" => "Someone"
                 },
                 "oauth_tokens" => %{"access_token" => "test-token"}
               })

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> AuthController.failure({:google, :register}, error)

      assert redirected_to(conn) == "/sign-in"

      flash = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash =~ "usetemi.com"

      assert Ash.count!(Ash.Query.filter(User, email == ^email), authorize?: false) == 0
    after
      Application.delete_env(:artifacts, :signup_email_domains)
    end
  end

  test "an OAuth failure with no allowed-domain restriction flashes a generic message", %{
    conn: conn
  } do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> AuthController.failure({:google, :callback}, :some_oauth_error)

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Sign-in failed."
  end

  test "sign-out clears the session and revokes the token", %{conn: conn} do
    user = user_fixture!()
    token = user.__metadata__.token
    conn = log_in_user(conn, user)

    conn = delete(conn, ~p"/sign-out")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "user_token") == nil

    # The revoked token no longer authenticates: presenting it in a fresh
    # session does not sign the request in.
    reused_conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:host, Application.fetch_env!(:artifacts, :app_host))
      |> Phoenix.ConnTest.init_test_session(%{"user_token" => token})

    reused_conn = get(reused_conn, ~p"/")
    assert redirected_to(reused_conn) == "/sign-in"
  end
end
