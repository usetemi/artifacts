defmodule ArtifactsWeb.AuthController do
  @moduledoc """
  `success/4` and `failure/3` callbacks for `auth_routes` (Google sign-in).
  `failure/3` covers both a genuine OAuth2 failure and a rejected sign-up
  (`Artifacts.Accounts.User.Changes.RejectUnverifiedOrDisallowedDomain`,
  which adds an `Ash.Changeset` error rather than raising, so no `User` row
  is ever written for either case — see `notes/ash_authentication.md §1.6`).
  """

  use ArtifactsWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @impl true
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  @impl true
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, failure_message())
    |> redirect(to: ~p"/sign-in")
  end

  @impl true
  def sign_out(conn, _params) do
    conn
    |> clear_session(:artifacts)
    |> redirect(to: ~p"/")
  end

  defp failure_message do
    case allowed_domains() do
      [] -> "Sign-in failed."
      domains -> "Sign-in failed. Only #{format_domains(domains)} Google accounts can sign up."
    end
  end

  defp allowed_domains do
    :artifacts
    |> Application.get_env(:signup_email_domains, "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp format_domains(domains) do
    domains |> Enum.map(&"@#{&1}") |> Enum.join(", ")
  end
end
