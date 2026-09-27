defmodule ArtifactsWeb.ArtifactsLive do
  @moduledoc """
  The open Artifacts of the selected Organization, with an Organization
  switcher over the User's Memberships and an archived filter (DESIGN.md
  "Web app").
  """

  use ArtifactsWeb, :live_view

  alias Artifacts.Accounts
  alias Artifacts.Publishing

  @impl true
  def mount(_params, _session, socket) do
    organizations = Accounts.list_organizations!(actor: socket.assigns.current_user)
    {:ok, assign(socket, organizations: organizations, page_title: "Artifacts")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user
    organization = select_organization(socket.assigns.organizations, params["org"], user)
    archived? = params["archived"] == "true"

    artifacts =
      Publishing.list_artifacts!(organization.id, %{archived: archived?}, actor: user)

    {:noreply,
     assign(socket, organization: organization, archived?: archived?, artifacts: artifacts)}
  end

  # Falls back to the User's Personal Organization, then to whichever
  # Organization comes first, so an unknown or omitted `org` param never
  # dead-ends the page — it just shows the default Organization instead.
  defp select_organization(organizations, org_id, user) do
    Enum.find(organizations, &(&1.id == org_id)) ||
      Enum.find(organizations, &(&1.id == user.personal_organization_id)) ||
      List.first(organizations)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Artifacts
        <:subtitle>Open pages in {@organization.name}</:subtitle>
      </.header>

      <form phx-change="switch_org" class="org-switcher" id="org-switcher">
        <label>
          Organization
          <select name="org">
            <option
              :for={organization <- @organizations}
              value={organization.id}
              selected={organization.id == @organization.id}
            >
              {organization.name}
            </option>
          </select>
        </label>
      </form>

      <div class="list-toolbar">
        <.link patch={list_path(@organization.id, !@archived?)} class="link">
          {if @archived?, do: "Show open", else: "Show archived"}
        </.link>
      </div>

      <p :if={@artifacts == []} class="empty-state">
        No {if @archived?, do: "archived", else: "open"} artifacts in this organization yet.
      </p>

      <.table :if={@artifacts != []} id="artifacts" rows={@artifacts}>
        <:col :let={artifact} label="Title">
          <.link navigate={~p"/a/#{artifact.id}"}>{artifact.title}</.link>
        </:col>
        <:col :let={artifact} label="Version">v{artifact.current_version}</:col>
        <:col :let={artifact} label="Updated">
          {Calendar.strftime(artifact.updated_at, "%Y-%m-%d %H:%M")}
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("switch_org", %{"org" => org_id}, socket) do
    {:noreply, push_patch(socket, to: list_path(org_id, socket.assigns.archived?))}
  end

  defp list_path(org_id, archived?) do
    "/?" <> URI.encode_query(%{"org" => org_id, "archived" => to_string(archived?)})
  end
end
