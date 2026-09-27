defmodule ArtifactsWeb.LiveUserAuth do
  @moduledoc """
  `on_mount` hooks for the web app's LiveViews (DESIGN.md "Web app"). Every
  LiveView other than the sign-in/sign-out pages is wrapped in
  `ash_authentication_live_session/2` with `:live_user_required`, which
  redirects a signed-out visitor to `/sign-in` before the LiveView's own
  `mount/3` runs. `:live_no_user` is used the other way, on the sign-in
  route, so an already-signed-in User skips past it to the Artifacts list.

  `ash_authentication_live_session/2` already assigns `current_user` (and
  `current_agent`, unused here) from the session before these hooks run, the
  same way `AshAuthentication.Phoenix.Router`'s own sign-in/sign-out routes
  do — see `notes/ash_authentication.md §5.4`.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  use ArtifactsWeb, :verified_routes

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end
end
