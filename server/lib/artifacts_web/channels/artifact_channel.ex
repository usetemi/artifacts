defmodule ArtifactsWeb.ArtifactChannel do
  @moduledoc """
  The one connection a page holds: `artifact:<id>` (DESIGN.md "Channel
  protocol"). The join reply is a snapshot (`version` and the flat `state`
  leaves, from `Publishing.get_leaves` — not `get_state`'s nested object,
  since this is what `state:ops` reapplies against on the wire); after
  that this channel relays `Artifacts.Publishing.ChannelNotifier`'s
  broadcasts as pushes (`state:ops`, `version` — never `submission`,
  which the chrome learns of from the same PubSub topic directly) and
  calls the same `Artifacts.Publishing` actions MCP and HTTP call, with
  the token's User as actor. Presence and `broadcast` never touch
  storage; they exist only while the page is open.
  """

  use ArtifactsWeb, :channel

  alias Artifacts.Publishing
  alias Artifacts.Publishing.{Actor, Errors}
  alias ArtifactsWeb.Presence

  @max_presence_meta_bytes 4096

  @impl true
  def join("artifact:" <> id, _params, socket) do
    if id == socket.assigns.artifact_id do
      do_join(id, socket)
    else
      # A token minted for a different artifact than this topic names.
      {:error, %{error: "not_found"}}
    end
  end

  defp do_join(id, socket) do
    opts = actor_opts(socket)

    with {:ok, artifact} <- Publishing.get_artifact(id, opts),
         :ok <- ensure_open(artifact),
         {:ok, leaves} <- Publishing.get_leaves(id, opts) do
      send(self(), :after_join)

      {:ok, %{version: artifact.current_version, state: leaves},
       assign(socket, :artifact, artifact)}
    else
      {:error, :archived} -> {:error, %{error: "archived"}}
      {:error, error} -> {:error, %{error: Errors.to_code(error)}}
    end
  end

  defp ensure_open(%{archived_at: nil}), do: :ok
  defp ensure_open(_archived_artifact), do: {:error, :archived}

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} =
      Presence.track(socket, presence_key(socket), %{name: socket.assigns.actor.name, meta: %{}})

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:version, %{version: number, by: by}}, socket) do
    push(socket, "version", %{version: number, by: by})
    {:noreply, socket}
  end

  def handle_info({:state_ops, %{ops: ops, by: by}}, socket) do
    push(socket, "state:ops", %{ops: ops, by: by})
    {:noreply, socket}
  end

  # No `submission` push reaches pages (DESIGN.md's channel protocol
  # table has no such row): the chrome subscribes to this same topic
  # directly for that instead. Still received here since every joined
  # channel process is subscribed to the whole topic.
  def handle_info({:submission, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_in("state:ops", %{"ops" => ops}, socket) do
    case Publishing.change_state(socket.assigns.artifact, ops, actor_opts(socket)) do
      {:ok, _artifact} -> {:reply, :ok, socket}
      {:error, error} -> {:reply, {:error, %{error: Errors.to_code(error)}}, socket}
    end
  end

  def handle_in("presence:update", %{"meta" => meta}, socket) when is_map(meta) do
    if byte_size(Jason.encode!(meta)) > @max_presence_meta_bytes do
      {:reply, {:error, %{error: "invalid"}}, socket}
    else
      {:ok, _ref} = Presence.update(socket, presence_key(socket), &%{&1 | meta: meta})
      {:reply, :ok, socket}
    end
  end

  def handle_in("presence:update", _params, socket) do
    {:reply, {:error, %{error: "invalid"}}, socket}
  end

  def handle_in("broadcast", %{"topic" => topic, "data" => data}, socket) when is_binary(topic) do
    broadcast_from!(socket, "broadcast", %{
      topic: topic,
      data: data,
      from: Actor.ref(socket.assigns.actor, %{})
    })

    {:noreply, socket}
  end

  def handle_in("submit", params, socket) do
    payload = Map.get(params, "payload")

    case Publishing.submit(socket.assigns.artifact, payload, actor_opts(socket)) do
      {:ok, artifact} -> {:reply, {:ok, %{id: artifact.__metadata__.submission_id}}, socket}
      {:error, error} -> {:reply, {:error, %{error: Errors.to_code(error)}}, socket}
    end
  end

  def handle_in("publish", %{"html" => html} = params, socket) do
    if_version = Map.get(params, "if_version")

    case Publishing.publish(socket.assigns.artifact, html, if_version, actor_opts(socket)) do
      {:ok, artifact} -> {:reply, {:ok, %{version: artifact.current_version}}, socket}
      {:error, error} -> {:reply, {:error, %{error: Errors.to_code(error)}}, socket}
    end
  end

  defp presence_key(socket), do: to_string(socket.assigns.actor.id)

  # Only Users open this socket (ArtifactSocket's own doc), so no Harness
  # ever attributes a write made through it.
  defp actor_opts(socket) do
    [actor: socket.assigns.actor, context: %{shared: %{harness_id: nil, harness_name: nil}}]
  end
end
