defmodule Artifacts.Accounts.User.Changes.RejectUnverifiedOrDisallowedDomain do
  @moduledoc """
  Rejects `register_with_google` when Google reports the email as
  unverified, or the email's domain is not in `SIGNUP_EMAIL_DOMAINS`
  (`config :artifacts, :signup_email_domains`, comma-separated; empty or
  unset means any domain is allowed).

  Runs as a plain changeset change on a `create` action, so adding an
  error here stops the pipeline before the data layer's insert: no `User`
  row is written for a rejected sign-up. Google's `email_verified` claim is
  not guaranteed to arrive as a JSON boolean rather than the string
  `"true"`, so both are accepted.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info) || %{}
    email_verified? = Map.get(user_info, "email_verified") in [true, "true"]
    email = Map.get(user_info, "email")
    domain = email && email |> String.split("@") |> List.last() |> String.downcase()

    cond do
      not email_verified? ->
        Ash.Changeset.add_error(changeset,
          field: :email,
          message: "Google account email is not verified"
        )

      not domain_allowed?(domain) ->
        Ash.Changeset.add_error(changeset,
          field: :email,
          message: "email domain is not allowed to sign up"
        )

      true ->
        changeset
    end
  end

  defp domain_allowed?(domain) do
    case allowed_domains() do
      [] -> true
      domains -> domain in domains
    end
  end

  defp allowed_domains do
    :artifacts
    |> Application.get_env(:signup_email_domains, "")
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  end
end
