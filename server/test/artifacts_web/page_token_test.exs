defmodule ArtifactsWeb.PageTokenTest do
  use Artifacts.DataCase, async: true

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias ArtifactsWeb.PageToken

  test "sign/verify round-trips, reloading the User and re-checking the Artifact" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)

    token = PageToken.sign(artifact.id, user.id)
    assert {:ok, %{artifact: verified_artifact, user: verified_user}} = PageToken.verify(token)
    assert verified_artifact.id == artifact.id
    assert verified_user.id == user.id
  end

  test "an expired token is refused" do
    user = user_fixture!()
    artifact = artifact_fixture!(user)

    token =
      Phoenix.Token.sign(
        ArtifactsWeb.Endpoint,
        "artifact page v1",
        %{
          artifact_id: artifact.id,
          user_id: user.id
        },
        signed_at: System.system_time(:second) - 601
      )

    assert {:error, :expired} = PageToken.verify(token)
  end

  test "a tampered token is invalid" do
    assert {:error, :invalid} = PageToken.verify("not-a-real-token")
  end

  test "a non-member's token fails re-verification against the Artifact policy" do
    owner = user_fixture!()
    artifact = artifact_fixture!(owner)
    stranger = user_fixture!()

    token = PageToken.sign(artifact.id, stranger.id)
    assert {:error, :not_found} = PageToken.verify(token)
  end
end
