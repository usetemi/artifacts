defmodule ArtifactsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ArtifactsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ArtifactsWeb.Endpoint

      use ArtifactsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ArtifactsWeb.ConnCase
    end
  end

  setup tags do
    Artifacts.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Signs a User into the session the way `AshAuthentication.Phoenix.
  Controller`'s `success/4` does, without going through the Google OAuth2
  handshake. The User must already carry `__metadata__.token`, i.e. must
  have been created through `register_with_google` (see
  `Artifacts.AccountsFixtures.user_fixture/1`), since
  `require_token_presence_for_authentication?` stores the raw JWT in the
  session.
  """
  def log_in_user(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
