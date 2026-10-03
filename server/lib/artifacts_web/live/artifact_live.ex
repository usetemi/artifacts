defmodule ArtifactsWeb.ArtifactLive do
  @moduledoc """
  The chrome around a published page (DESIGN.md "Web app", "Page origin and
  runtime"): title, Version, live Presence, rename, archive/unarchive, and
  Submit. The page itself lives in an iframe on the content origin; the
  chrome never tracks itself as a Viewer (plan §7) — Presence names come
  from `ArtifactsWeb.Presence.list/1` on the same topic the page channel
  tracks Viewers on.

  A new Version arrives over the same `Artifacts.Publishing.
  ChannelNotifier` broadcast the page channel translates for pages: the
  chrome mints a fresh page token and pushes a new iframe `src` rather than
  reloading the frame (which only works same-origin), via the
  `ArtifactChrome` JS hook (`assets/js/artifact_chrome.js`).
  """

  use ArtifactsWeb, :live_view

  alias Artifacts.Publishing
  alias Artifacts.Publishing.{Artifact, Errors}
  alias ArtifactsWeb.{Origins, PageToken, Presence}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Ash.get(Artifact, id, actor: user) do
      {:ok, artifact} ->
        topic = "artifact:#{artifact.id}"

        if connected?(socket) do
          :ok = Phoenix.PubSub.subscribe(Artifacts.PubSub, topic)
        end

        {:ok,
         socket
         |> assign(
           artifact: artifact,
           topic: topic,
           editing_title?: false,
           submitted: nil,
           viewer_names: viewer_names(topic),
           page_title: "#{artifact.title} · Artifacts"
         )}

      {:error, _error} ->
        raise ArtifactsWeb.NotFoundError
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_bleed>
      <div id="chrome" class="chrome">
        <header class="chrome-bar">
          <div class="chrome-title">
            <.link navigate={~p"/"} class="chrome-back">Artifacts</.link>

            <%= if @editing_title? do %>
              <form phx-submit="save_title" class="chrome-title-form" id="rename-form">
                <input
                  type="text"
                  name="title"
                  value={@artifact.title}
                  class="input"
                  autofocus
                  required
                />
                <button type="submit" class="btn">Save</button>
                <button type="button" class="btn" phx-click="cancel_title">Cancel</button>
              </form>
            <% else %>
              <h1>{@artifact.title}</h1>
              <button
                :if={!@artifact.archived_at}
                type="button"
                class="chrome-rename"
                phx-click="edit_title"
              >
                Rename
              </button>
            <% end %>

            <span class="chrome-meta">
              v{@artifact.current_version} · {viewer_label(@viewer_names)}
              <span :if={@artifact.archived_at} class="badge badge-archived">Archived</span>
            </span>
          </div>

          <div class="chrome-actions">
            <span :if={@submitted} id="submitted" class="chrome-note">
              Submission {@submitted} sent
            </span>

            <button :if={@artifact.archived_at} type="button" class="btn" phx-click="unarchive">
              Unarchive
            </button>
            <button
              :if={!@artifact.archived_at}
              type="button"
              class="btn btn-danger"
              phx-click="archive"
              data-confirm="Archive this artifact? It stays readable, but no more changes can be made."
            >
              Archive
            </button>
          </div>
        </header>

        <%= if @artifact.archived_at do %>
          <div class="chrome-archived">
            <p>This artifact is archived. Its Versions, State, and History stay readable.</p>
          </div>
        <% else %>
          <iframe
            id="page"
            title={@artifact.title}
            src={content_page_url(@artifact.id, @current_user.id)}
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-modals allow-downloads"
            phx-hook="ArtifactChrome"
            phx-update="ignore"
            data-content-origin={Origins.content_origin()}
          />
          <form phx-submit="submit" class="chrome-submit" id="submit-form">
            <textarea name="note" class="textarea" placeholder="Optional note" rows="2"></textarea>
            <button type="submit" class="btn btn-primary" id="submit">Submit</button>
          </form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("edit_title", _params, socket) do
    {:noreply, assign(socket, editing_title?: true)}
  end

  def handle_event("cancel_title", _params, socket) do
    {:noreply, assign(socket, editing_title?: false)}
  end

  def handle_event("save_title", %{"title" => title}, socket) do
    case Publishing.rename(socket.assigns.artifact, title, actor: socket.assigns.current_user) do
      {:ok, artifact} ->
        {:noreply,
         socket
         |> assign(
           artifact: artifact,
           editing_title?: false,
           page_title: "#{artifact.title} · Artifacts"
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("archive", _params, socket) do
    case Publishing.archive(socket.assigns.artifact, actor: socket.assigns.current_user) do
      {:ok, artifact} -> {:noreply, assign(socket, artifact: artifact)}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("unarchive", _params, socket) do
    case Publishing.unarchive(socket.assigns.artifact, actor: socket.assigns.current_user) do
      {:ok, artifact} -> {:noreply, assign(socket, artifact: artifact)}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("submit", %{"note" => note}, socket) do
    payload =
      case String.trim(note) do
        "" -> nil
        trimmed -> %{"note" => trimmed}
      end

    case Publishing.submit(socket.assigns.artifact, payload, actor: socket.assigns.current_user) do
      {:ok, submitted} ->
        {:noreply, assign(socket, submitted: submitted.__metadata__.submission_id)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("page_token", _params, socket) do
    token = PageToken.sign(socket.assigns.artifact.id, socket.assigns.current_user.id)
    {:reply, %{token: token}, socket}
  end

  @impl true
  def handle_info({:version, %{version: number}}, socket) do
    artifact = %{socket.assigns.artifact | current_version: number}
    src = content_page_url(artifact.id, socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(artifact: artifact)
     |> push_event("page:reload", %{src: src})}
  end

  def handle_info({:submission, %{id: id}}, socket) do
    {:noreply, assign(socket, submitted: id)}
  end

  def handle_info({:state_ops, _payload}, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, viewer_names: viewer_names(socket.assigns.topic))}
  end

  defp viewer_names(topic) do
    topic
    |> Presence.list()
    |> Enum.map(fn {_id, %{metas: [meta | _]}} -> meta.name end)
  end

  defp viewer_label([]), do: "no one else here"
  defp viewer_label([_one]), do: "1 viewer"
  defp viewer_label(names), do: "#{length(names)} viewers"

  defp content_page_url(artifact_id, user_id) do
    token = PageToken.sign(artifact_id, user_id)

    Origins.content_origin()
    |> URI.parse()
    |> Map.merge(%{path: "/a/#{artifact_id}/page", query: URI.encode_query(%{"t" => token})})
    |> URI.to_string()
  end

  defp error_message(error) do
    case Errors.to_code(error) do
      "archived" -> "This artifact is no longer open."
      "quota" -> "This artifact has reached its submission limit."
      "conflict" -> "Someone else changed this artifact first."
      "forbidden" -> "You don't have access to do that."
      _other -> "Something went wrong."
    end
  end
end
