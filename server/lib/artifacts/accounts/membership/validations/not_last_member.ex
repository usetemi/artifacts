defmodule Artifacts.Accounts.Membership.Validations.NotLastMember do
  @moduledoc """
  Locks the Membership's organization row (`SELECT ... FOR UPDATE`) and
  refuses the destroy when it is that organization's last Membership, so
  two concurrent removals of an organization's last two members can't both
  succeed. Runs as a `before_action?` validation so the lock and the count
  happen inside the destroy action's own transaction, on both `:remove`
  and `:leave` (matched by action type, not name).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    organization_id = changeset.data.organization_id

    Artifacts.Accounts.Organization
    |> Ash.Query.filter(id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)

    remaining_members =
      Artifacts.Accounts.Membership
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> Ash.count!(authorize?: false)

    if remaining_members <= 1 do
      {:error, field: :organization_id, message: "cannot remove the organization's last member"}
    else
      :ok
    end
  end
end
