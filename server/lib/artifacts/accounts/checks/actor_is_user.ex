defmodule Artifacts.Accounts.Checks.ActorIsUser do
  @moduledoc """
  A reusable `Ash.Policy.SimpleCheck`: true when the actor is an
  `Artifacts.Accounts.User`. Paired with `Artifacts.Accounts.Checks.
  ActorIsAgent` to branch an organization-scoped resource's read policy by
  actor type, since a `User` and an `Agent` reach the same organization
  through different columns and have no shared attribute to filter on.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is a user"

  @impl true
  def match?(%Artifacts.Accounts.User{}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
