defmodule ArtifactsWeb.AuthController do
  @moduledoc """
  `success/4` and `failure/3` callbacks for `auth_routes` (Google
  sign-in). No page routes exist yet to redirect to, so the redirect
  targets are plain strings rather than `~p` sigils; slice D's LiveViews
  and sign-in page replace them.
  """

  use ArtifactsWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @impl true
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || "/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  @impl true
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Sign-in failed.")
    |> redirect(to: "/sign-in")
  end

  @impl true
  def sign_out(conn, _params) do
    conn
    |> clear_session(:artifacts)
    |> redirect(to: "/")
  end
end
