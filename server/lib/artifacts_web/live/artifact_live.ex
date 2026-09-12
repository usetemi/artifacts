defmodule ArtifactsWeb.ArtifactLive do
  @moduledoc """
  The chrome around a published page: title, version, who is viewing,
  and the Submit button. The page itself lives in an iframe that the
  chrome reloads when a new version is published; state survives the
  reload because it lives in Postgres, not in the page.
  """

  use ArtifactsWeb, :live_view

  alias Artifacts.Store
  alias ArtifactsWeb.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Store.get(id) do
      {:ok, artifact} ->
        if connected?(socket) do
          :ok = Phoenix.PubSub.subscribe(Artifacts.PubSub, Store.topic(id))
        end

        {:ok,
         assign(socket,
           artifact: artifact,
           version: artifact.current_version,
           viewers: viewer_count(id),
           submitted: nil,
           page_title: artifact.title
         )}

      {:error, :not_found} ->
        raise ArtifactsWeb.NotFoundError
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chrome" class="chrome">
      <header class="chrome-bar">
        <div class="chrome-title">
          <h1>{@artifact.title}</h1>
          <span class="chrome-meta">v{@version} · {viewer_label(@viewers)}</span>
        </div>
        <div class="chrome-actions">
          <span :if={@submitted} id="submitted" class="chrome-note">Submission {@submitted} sent</span>
          <button id="submit" type="button" phx-click={JS.dispatch("artifacts:submit", to: "#page")}>
            Submit
          </button>
        </div>
      </header>
      <iframe
        id="page"
        title={@artifact.title}
        src={~p"/a/#{@artifact.id}/page"}
        sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-modals allow-downloads"
        phx-hook=".Chrome"
        phx-update="ignore"
      ></iframe>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Chrome">
        export default {
          mounted() {
            // The page's runtime knows the viewer id; reading it through the
            // same-origin frame keeps one definition of "viewer".
            this.el.addEventListener("artifacts:submit", () => {
              const viewer = this.el.contentWindow?.artifact?.viewer?.id ?? null
              this.pushEvent("submit", {viewer_id: viewer})
            })
            this.handleEvent("reload", () => this.el.contentWindow.location.reload())
          },
        }
      </script>
    </div>
    """
  end

  @impl true
  def handle_event("submit", params, socket) do
    case Store.submit(socket.assigns.artifact.id, nil, params["viewer_id"]) do
      {:ok, submission} ->
        {:noreply, assign(socket, submitted: submission.id)}

      {:error, :quota} ->
        {:noreply, put_flash(socket, :error, "This artifact has reached its submission limit.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "This artifact was deleted.")}
    end
  end

  @impl true
  def handle_info({:version, number, _by}, socket) do
    {:noreply, socket |> assign(version: number) |> push_event("reload", %{})}
  end

  def handle_info({:submission, submission}, socket) do
    {:noreply, assign(socket, submitted: submission.id)}
  end

  def handle_info({:state_ops, _ops, _by}, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, viewers: viewer_count(socket.assigns.artifact.id))}
  end

  defp viewer_count(id), do: id |> Store.topic() |> Presence.list() |> map_size()

  defp viewer_label(1), do: "1 viewer"
  defp viewer_label(n), do: "#{n} viewers"
end
