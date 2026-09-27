defmodule ArtifactsWeb.ArtifactSocket do
  @moduledoc """
  The page socket, mounted at `/socket` on the content host only
  (DESIGN.md "Page origin and runtime", "Socket"). The runtime connects
  with the page token as a connect param; `connect/3` verifies it the same
  way the page route does and assigns the resolved User as `:actor` and
  the token's own artifact id as `:artifact_id`. `ArtifactsWeb.
  ArtifactChannel.join/3` then requires that a join's topic names this
  same artifact id, refusing a token minted for a different artifact.

  MVP viewers are browser Users only (`ArtifactsWeb.PageToken`'s own
  doc): Harnesses and Agents act over MCP/HTTP and never open this
  socket.
  """

  use Phoenix.Socket

  alias ArtifactsWeb.PageToken

  channel "artifact:*", ArtifactsWeb.ArtifactChannel

  @impl true
  def connect(%{"t" => token}, socket, _connect_info) do
    case PageToken.verify(token) do
      {:ok, %{artifact: artifact, user: user}} ->
        {:ok, socket |> assign(:actor, user) |> assign(:artifact_id, artifact.id)}

      {:error, _expired_invalid_or_not_found} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # No per-user disconnect surface exists yet, so no identifier is needed
  # to reach a User's sockets later.
  @impl true
  def id(_socket), do: nil
end
