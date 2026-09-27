defmodule ArtifactsWeb.SettingsLive do
  @moduledoc """
  Create an Organization; add or remove a member by email, or leave;
  create an Agent and issue or revoke its keys; create or revoke a Harness
  (DESIGN.md "Web app"). A new key's plaintext is shown once, right after
  creation, with the `claude mcp add` command from DESIGN.md's "Agent
  interfaces" section filled in for this Instance's app origin.
  """

  use ArtifactsWeb, :live_view

  alias Artifacts.Accounts
  alias Artifacts.Accounts.{Harness, Organization}

  @default_expiry_days 365

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organizations = Accounts.list_organizations!(actor: user)

    {:ok,
     assign(socket,
       organizations: organizations,
       harnesses: Ash.read!(Harness, actor: user),
       revealed_key: nil,
       page_title: "Settings"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    organization =
      socket.assigns.organizations
      |> select_organization(params["org"], socket.assigns.current_user)
      |> load_details()

    {:noreply, assign(socket, organization: organization)}
  end

  defp select_organization(organizations, org_id, user) do
    Enum.find(organizations, &(&1.id == org_id)) ||
      Enum.find(organizations, &(&1.id == user.personal_organization_id)) ||
      List.first(organizations)
  end

  # The parent Organization was already fetched under the actor's own
  # policy-filtered list, so loading its members' User records and its
  # Agents' keys with authorize?: false is safe (same pattern as
  # Artifact.history's own actor-ref loading) and avoids User's
  # id == actor(:id) read policy blanking out co-members.
  defp load_details(organization) do
    Ash.load!(organization, [memberships: [:user], agents: [:agent_keys]], authorize?: false)
  end

  defp reload_organization(socket) do
    organization =
      Organization
      |> Ash.get!(socket.assigns.organization.id, actor: socket.assigns.current_user)
      |> load_details()

    assign(socket, organization: organization)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Settings</.header>

      <div :if={@revealed_key} id="revealed-key" class="revealed-key">
        <p>
          <strong>{@revealed_key.name}</strong>'s key — shown once, copy it now:
        </p>
        <code class="revealed-key-plaintext">{@revealed_key.plaintext}</code>
        <p>Connect it as a harness:</p>
        <pre class="revealed-key-command">{@revealed_key.command}</pre>
        <button type="button" class="btn" phx-click="dismiss_key">Dismiss</button>
      </div>

      <section class="settings-section">
        <h2>Organizations</h2>

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

        <form phx-submit="create_organization" id="create-organization-form" class="inline-form">
          <input type="text" name="name" placeholder="New organization name" required class="input" />
          <button type="submit" class="btn btn-primary">Create Organization</button>
        </form>
      </section>

      <section class="settings-section">
        <h2>Members</h2>

        <table class="table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Name</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={membership <- @organization.memberships} id={"membership-#{membership.id}"}>
              <td>{membership.user.email}</td>
              <td>{membership.user.name}</td>
              <td>
                <%= if membership.user_id == @current_user.id do %>
                  <button
                    type="button"
                    class="btn btn-danger"
                    phx-click="leave"
                    phx-value-id={membership.id}
                    disabled={length(@organization.memberships) <= 1}
                    data-confirm="Leave this organization?"
                  >
                    Leave
                  </button>
                <% else %>
                  <button
                    type="button"
                    class="btn btn-danger"
                    phx-click="remove_member"
                    phx-value-id={membership.id}
                    data-confirm="Remove this member?"
                  >
                    Remove
                  </button>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>

        <form phx-submit="add_member" id="add-member-form" class="inline-form">
          <input type="email" name="email" placeholder="Member's email" required class="input" />
          <button type="submit" class="btn btn-primary">Add Member</button>
        </form>
      </section>

      <section class="settings-section">
        <h2>Agents</h2>

        <div :for={agent <- @organization.agents} id={"agent-#{agent.id}"} class="card">
          <h3>{agent.name}</h3>
          <ul class="key-list">
            <li :for={key <- agent.agent_keys} id={"agent-key-#{key.id}"}>
              <span>{key.name}</span>
              <%= if key.revoked_at do %>
                <span class="badge">Revoked</span>
              <% else %>
                <button type="button" class="btn" phx-click="revoke_agent_key" phx-value-id={key.id}>
                  Revoke
                </button>
              <% end %>
            </li>
          </ul>
          <button type="button" class="btn" phx-click="create_agent_key" phx-value-agent_id={agent.id}>
            Issue key
          </button>
        </div>

        <form phx-submit="create_agent" id="create-agent-form" class="inline-form">
          <input type="text" name="name" placeholder="Agent name" required class="input" />
          <button type="submit" class="btn btn-primary">Create Agent</button>
        </form>
      </section>

      <section class="settings-section">
        <h2>Your Harnesses</h2>

        <ul class="key-list">
          <li :for={harness <- @harnesses} id={"harness-#{harness.id}"}>
            <span>{harness.name}</span>
            <%= if harness.revoked_at do %>
              <span class="badge">Revoked</span>
            <% else %>
              <button type="button" class="btn" phx-click="revoke_harness" phx-value-id={harness.id}>
                Revoke
              </button>
            <% end %>
          </li>
        </ul>

        <form phx-submit="create_harness" id="create-harness-form" class="inline-form">
          <input
            type="text"
            name="name"
            placeholder="e.g. Victor's Claude Code on kanto"
            required
            class="input"
          />
          <button type="submit" class="btn btn-primary">Create Harness</button>
        </form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("switch_org", %{"org" => org_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings?org=#{org_id}")}
  end

  def handle_event("create_organization", %{"name" => name}, socket) do
    case Accounts.create_organization(name, actor: socket.assigns.current_user) do
      {:ok, organization} ->
        organizations = Accounts.list_organizations!(actor: socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(organizations: organizations)
         |> push_patch(to: ~p"/settings?org=#{organization.id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("add_member", %{"email" => email}, socket) do
    case Accounts.add_member(socket.assigns.organization.id, email,
           actor: socket.assigns.current_user
         ) do
      {:ok, _membership} -> {:noreply, reload_organization(socket)}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    with membership when not is_nil(membership) <- find_membership(socket, id),
         :ok <- Accounts.remove_member(membership, actor: socket.assigns.current_user) do
      {:noreply, reload_organization(socket)}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("leave", %{"id" => id}, socket) do
    with membership when not is_nil(membership) <- find_membership(socket, id),
         :ok <- Accounts.leave(membership, actor: socket.assigns.current_user) do
      organizations = Accounts.list_organizations!(actor: socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(organizations: organizations)
       |> push_patch(to: ~p"/settings")}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("create_agent", %{"name" => name}, socket) do
    case Accounts.create_agent(socket.assigns.organization.id, name,
           actor: socket.assigns.current_user
         ) do
      {:ok, _agent} -> {:noreply, reload_organization(socket)}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("create_agent_key", %{"agent_id" => agent_id}, socket) do
    case Accounts.create_agent_key(agent_id, "Key", default_expiry(),
           actor: socket.assigns.current_user
         ) do
      {:ok, agent_key} ->
        {:noreply,
         socket
         |> assign(revealed_key: reveal(agent_key))
         |> reload_organization()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("revoke_agent_key", %{"id" => id}, socket) do
    with key when not is_nil(key) <- find_agent_key(socket, id),
         {:ok, _} <- Accounts.revoke_agent_key(key, actor: socket.assigns.current_user) do
      {:noreply, reload_organization(socket)}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("create_harness", %{"name" => name}, socket) do
    user = socket.assigns.current_user

    case Accounts.create_harness(user.id, name, default_expiry(), actor: user) do
      {:ok, harness} ->
        {:noreply,
         assign(socket, revealed_key: reveal(harness), harnesses: Ash.read!(Harness, actor: user))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("revoke_harness", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with harness when not is_nil(harness) <- find_harness(socket, id),
         {:ok, _} <- Accounts.revoke_harness(harness, actor: user) do
      {:noreply, assign(socket, harnesses: Ash.read!(Harness, actor: user))}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, put_flash(socket, :error, friendly_error(error))}
    end
  end

  def handle_event("dismiss_key", _params, socket) do
    {:noreply, assign(socket, revealed_key: nil)}
  end

  defp find_membership(socket, id),
    do: Enum.find(socket.assigns.organization.memberships, &(&1.id == id))

  defp find_agent_key(socket, id) do
    socket.assigns.organization.agents
    |> Enum.flat_map(& &1.agent_keys)
    |> Enum.find(&(&1.id == id))
  end

  defp find_harness(socket, id), do: Enum.find(socket.assigns.harnesses, &(&1.id == id))

  defp default_expiry, do: DateTime.add(DateTime.utc_now(), @default_expiry_days, :day)

  defp reveal(key_or_harness) do
    plaintext = key_or_harness.__metadata__.plaintext_api_key

    %{name: key_or_harness.name, plaintext: plaintext, command: mcp_command(plaintext)}
  end

  defp mcp_command(plaintext_key) do
    """
    claude mcp add --transport http artifacts #{ArtifactsWeb.Origins.app_origin()}/mcp \\
      --header "Authorization: Bearer #{plaintext_key}"\
    """
  end

  defp friendly_error(%Ash.Error.Invalid{errors: [first | _]}), do: Exception.message(first)
  defp friendly_error(error), do: Exception.message(error)
end
