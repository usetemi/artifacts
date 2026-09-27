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

  @doc """
  The MFA predicate behind this socket's `check_origin` (set in
  `ArtifactsWeb.Endpoint`): the content origin only, resolved at request
  time since `ArtifactsWeb.Origins` reads runtime config. A literal list
  written directly in `endpoint.ex` would instead be frozen at compile
  time, into whichever environment happened to compile the release.
  """
  @spec check_origin?(URI.t()) :: boolean()
  def check_origin?(%URI{} = uri) do
    URI.to_string(uri) == ArtifactsWeb.Origins.content_origin()
  end
end
