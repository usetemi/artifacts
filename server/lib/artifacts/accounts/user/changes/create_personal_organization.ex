defmodule Artifacts.Accounts.User.Changes.CreatePersonalOrganization do
  @moduledoc """
  After `register_with_google` inserts or upserts a `User`, creates that
  User's Personal Organization (which creates its own first Membership, see
  `Artifacts.Accounts.Organization`'s `:create` action) in the same
  transaction, and sets `personal_organization_id`, when the User doesn't
  already have one.

  `register_with_google` upserts with `upsert_fields []`, so a repeat
  sign-in returns the row's already-persisted `personal_organization_id`
  untouched — this makes a repeat sign-in's Personal Organization creation
  a no-op, matching DOMAIN.md's Sign-Up rule that no User exists without an
  Organization and a repeat sign-in changes nothing.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      if user.personal_organization_id do
        {:ok, user}
      else
        organization =
          Ash.create!(
            Artifacts.Accounts.Organization,
            %{name: personal_organization_name(user)},
            actor: user,
            authorize?: false
          )

        updated_user =
          user
          |> Ash.Changeset.for_update(
            :set_personal_organization,
            %{personal_organization_id: organization.id},
            actor: user
          )
          |> Ash.update!(authorize?: false)

        {:ok, updated_user}
      end
    end)
  end

  defp personal_organization_name(user) do
    "#{user.name || user.email}'s Organization"
  end
end
