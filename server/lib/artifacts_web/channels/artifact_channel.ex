defmodule ArtifactsWeb.ArtifactChannel do
  @moduledoc """
  The one connection a page holds: `artifact:<id>`.

  The join reply is a snapshot (`version` and the flat `state` leaves).
  After that the channel relays the store's PubSub messages as pushes
  (`state:ops`, `version`, `submission`) and accepts the page's writes,
  each of which goes through `Artifacts.Store` so the CLI and other pages
  learn about it the same way. Presence and `broadcast` never touch
  storage; they exist only while the page is open.
  """

  use ArtifactsWeb, :channel

  alias Artifacts.Store
  alias ArtifactsWeb.Presence

  @max_viewer_id_bytes 64

  @impl true
  def join("artifact:" <> id, params, socket) do
    with {:ok, artifact} <- Store.get_open(id),
         {:ok, viewer_id} <- viewer_id(params) do
      send(self(), :after_join)

      socket =
        assign(socket, artifact_id: id, viewer_id: viewer_id, by: Store.viewer(viewer_id))

      {:ok, %{version: artifact.current_version, state: Store.leaves(id)}, socket}
    else
      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      {:error, :archived} ->
        {:error, %{reason: "archived"}}

      {:error, :viewer_id} ->
        {:error, %{reason: "viewer_id must be a string of at most 64 bytes"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} = Presence.track(socket, socket.assigns.viewer_id, %{meta: %{}})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:state_ops, ops, by}, socket) do
    push(socket, "state:ops", %{ops: ops, by: by})
    {:noreply, socket}
  end

  def handle_info({:version, number, by}, socket) do
    push(socket, "version", %{version: number, by: by})
    {:noreply, socket}
  end

  def handle_info({:submission, submission}, socket) do
    push(socket, "submission", %{id: submission.id, viewer_id: submission.viewer_id})
    {:noreply, socket}
  end

  @impl true
  def handle_in("state:ops", %{"ops" => ops}, socket) do
    case Store.apply_ops(socket.assigns.artifact_id, ops, socket.assigns.by) do
      {:ok, _ops} -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("presence:update", %{"meta" => meta}, socket) when is_map(meta) do
    {:ok, _ref} =
      Presence.update(socket, socket.assigns.viewer_id, fn current ->
        %{current | meta: Map.merge(current.meta, meta)}
      end)

    {:reply, :ok, socket}
  end

  def handle_in("broadcast", %{"topic" => topic, "data" => data}, socket) when is_binary(topic) do
    broadcast_from!(socket, "broadcast", %{
      topic: topic,
      data: data,
      from: %{viewer: %{id: socket.assigns.viewer_id}}
    })

    {:noreply, socket}
  end

  def handle_in("submit", params, socket) do
    case Store.submit(socket.assigns.artifact_id, params["payload"], socket.assigns.viewer_id) do
      {:ok, submission} -> {:reply, {:ok, %{id: submission.id}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("publish", %{"html" => html} = params, socket) do
    opts = [by: socket.assigns.by] ++ if_version(params)

    case Store.publish(socket.assigns.artifact_id, html, opts) do
      {:ok, number} -> {:reply, {:ok, %{version: number}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  defp if_version(%{"if_version" => number}) when is_integer(number), do: [if_version: number]
  defp if_version(_params), do: []

  defp viewer_id(%{"viewer_id" => id})
       when is_binary(id) and id != "" and byte_size(id) <= @max_viewer_id_bytes do
    {:ok, id}
  end

  defp viewer_id(_params), do: {:error, :viewer_id}
end
