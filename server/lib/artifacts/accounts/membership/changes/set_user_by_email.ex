defmodule Artifacts.Accounts.Membership.Changes.SetUserByEmail do
  @moduledoc """
  Resolves the `:add_by_email` action's `email` argument to an existing
  User's id, or adds an error when no User has that email. Runs
  `authorize?: false` for the lookup itself: whether the email matches a
  User is a fact, not something the caller's own read policy should gate.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    email = Ash.Changeset.get_argument(changeset, :email)

    case Artifacts.Accounts.User
         |> Ash.Query.filter(email == ^email)
         |> Ash.read_one(authorize?: false) do
      {:ok, %Artifacts.Accounts.User{id: user_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset, field: :email, message: "no user with that email")

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
