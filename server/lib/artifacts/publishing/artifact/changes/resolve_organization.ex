defmodule Artifacts.Publishing.Artifact.Changes.ResolveOrganization do
  @moduledoc """
  Fills `organization_id` on `create` (DESIGN.md "Content changes"): the
  `organization_id` argument when given, else the actor's default — a
  User's (or a Harness-acting User's) Personal Organization, or an Agent's
  own Organization. The `create` action's own policy then checks the actor
  can act in whichever organization this resolves to, so naming an
  organization the actor cannot act in is forbidden the same way any other
  organization mismatch is.
  """

  use Ash.Resource.Change

  alias Artifacts.Accounts.{Agent, User}

  @impl true
  def change(changeset, _opts, context) do
    organization_id =
      Ash.Changeset.get_argument(changeset, :organization_id) ||
        default_organization_id(context.actor)

    Ash.Changeset.change_attribute(changeset, :organization_id, organization_id)
  end

  defp default_organization_id(%User{personal_organization_id: id}), do: id
  defp default_organization_id(%Agent{organization_id: id}), do: id
  defp default_organization_id(_other), do: nil
end
