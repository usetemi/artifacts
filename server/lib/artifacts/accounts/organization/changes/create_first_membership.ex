defmodule Artifacts.Accounts.Organization.Changes.CreateFirstMembership do
  @moduledoc """
  After an Organization is created, creates a Membership for the acting
  User in the same transaction, so no Organization ever exists without a
  member. Runs with `authorize?: false`: the `:create` action's own policy
  already established the actor may create an Organization at all.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    actor = context.actor

    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      Ash.create!(
        Artifacts.Accounts.Membership,
        %{user_id: actor.id, organization_id: organization.id},
        actor: actor,
        authorize?: false
      )

      {:ok, organization}
    end)
  end
end
