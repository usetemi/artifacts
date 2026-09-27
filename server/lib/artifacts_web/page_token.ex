defmodule ArtifactsWeb.PageToken do
  @moduledoc """
  Signs and verifies the 10-minute token that lets one User's browser open
  one Artifact's page on the content host (DESIGN.md "Page origin and
  runtime", "Page token"). `verify/1` never trusts the payload alone: it
  reloads the User and re-checks, under the real `Artifacts.Publishing.
  Artifact` policy, that the User can still read that Artifact — a
  revoked Membership between mint and use is caught here, not just at
  mint time.
  """

  @max_age_seconds 600
  @salt "artifact page v1"

  alias Artifacts.Accounts.User
  alias Artifacts.Publishing.Artifact

  @spec sign(String.t(), String.t()) :: String.t()
  def sign(artifact_id, user_id) do
    Phoenix.Token.sign(ArtifactsWeb.Endpoint, @salt, %{artifact_id: artifact_id, user_id: user_id})
  end

  @doc """
  Verifies the token's signature and age, reloads the User it names, and
  re-checks the Artifact policy for that User. Returns the reloaded
  Artifact and User on success.
  """
  @spec verify(String.t()) ::
          {:ok, %{artifact: Artifact.t(), user: User.t()}}
          | {:error, :expired | :invalid | :not_found}
  def verify(token) do
    with {:ok, %{artifact_id: artifact_id, user_id: user_id}} <- verify_signature(token),
         {:ok, user} <- Ash.get(User, user_id, authorize?: false),
         {:ok, artifact} <- Ash.get(Artifact, artifact_id, actor: user) do
      {:ok, %{artifact: artifact, user: user}}
    else
      {:error, :expired} -> {:error, :expired}
      {:error, :invalid} -> {:error, :invalid}
      _not_found_or_missing_user -> {:error, :not_found}
    end
  end

  defp verify_signature(token) do
    Phoenix.Token.verify(ArtifactsWeb.Endpoint, @salt, token, max_age: @max_age_seconds)
  end
end
