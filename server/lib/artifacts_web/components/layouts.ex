defmodule ArtifactsWeb.Layouts do
  @moduledoc false

  use ArtifactsWeb, :html

  embed_templates "layouts/*"

  @doc """
  The app-wide layout: a top nav (Artifacts / Settings / who's signed in /
  sign out) around the page content, plus the flash group. `full_bleed`
  skips the nav for the artifact chrome (DESIGN.md "Web app"), which owns
  the whole viewport height for its own title bar and the page iframe.
  """
  attr :flash, :map, required: true
  attr :current_user, :any, default: nil
  attr :full_bleed, :boolean, default: false

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @full_bleed do %>
      {render_slot(@inner_block)}
    <% else %>
      <div class="page">
        <.nav current_user={@current_user} />
        <main class="page-main">
          {render_slot(@inner_block)}
        </main>
      </div>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_user, :any, default: nil

  defp nav(assigns) do
    ~H"""
    <header class="topnav">
      <.link navigate={~p"/"} class="topnav-brand">Artifacts</.link>
      <nav :if={@current_user} class="topnav-links">
        <.link navigate={~p"/"}>Artifacts</.link>
        <.link navigate={~p"/settings"}>Settings</.link>
        <span class="topnav-user">{@current_user.name || @current_user.email}</span>
        <.link href={~p"/sign-out"} method="delete">Sign out</.link>
      </nav>
    </header>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
