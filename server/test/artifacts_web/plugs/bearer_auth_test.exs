defmodule ArtifactsWeb.Plugs.BearerAuthTest do
  use Artifacts.DataCase, async: true

  import Artifacts.AccountsFixtures

  alias ArtifactsWeb.Plugs.BearerAuth

  defp conn_with_bearer(nil) do
    Plug.Test.conn(:get, "/")
  end

  defp conn_with_bearer(key) do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Conn.put_req_header("authorization", "Bearer #{key}")
  end

  defp call(key) do
    key
    |> conn_with_bearer()
    |> BearerAuth.call(BearerAuth.init([]))
  end

  test "an arth key signs in the Harness's User and records the harness in shared context" do
    user = user_fixture!()
    harness = harness_fixture!(user)
    key = harness.__metadata__.plaintext_api_key

    conn = call(key)

    refute conn.halted
    assert conn.assigns.current_user.id == user.id
    assert Ash.PlugHelpers.get_context(conn).shared.harness_id == harness.id
    assert Ash.PlugHelpers.get_context(conn).shared.harness_name == harness.name
  end

  test "an arta key signs in the Agent" do
    owner = user_fixture!()
    organization = organization_fixture!(owner)
    agent = agent_fixture!(organization, owner)
    agent_key = agent_key_fixture!(agent, owner)
    key = agent_key.__metadata__.plaintext_api_key

    conn = call(key)

    refute conn.halted
    assert conn.assigns.current_agent.id == agent.id
  end

  test "a revoked arth key is rejected with 401" do
    user = user_fixture!()
    harness = harness_fixture!(user)
    key = harness.__metadata__.plaintext_api_key
    Artifacts.Accounts.revoke_harness!(harness, actor: user)

    conn = call(key)

    assert conn.halted
    assert conn.status == 401
  end

  test "an expired arta key is rejected with 401" do
    owner = user_fixture!()
    organization = organization_fixture!(owner)
    agent = agent_fixture!(organization, owner)

    agent_key =
      agent_key_fixture!(agent, owner, expires_at: DateTime.add(DateTime.utc_now(), -1, :day))

    key = agent_key.__metadata__.plaintext_api_key

    conn = call(key)

    assert conn.halted
    assert conn.status == 401
  end

  test "an unrecognized prefix is rejected with 401" do
    conn = call("bogus_notaprefix_xyz")

    assert conn.halted
    assert conn.status == 401
  end

  test "a missing Authorization header is rejected with 401" do
    conn = call(nil)

    assert conn.halted
    assert conn.status == 401
  end
end
