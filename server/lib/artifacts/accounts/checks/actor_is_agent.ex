defmodule Artifacts.Accounts.Checks.ActorIsAgent do
  @moduledoc """
  A reusable `Ash.Policy.SimpleCheck`: true when the actor is an
  `Artifacts.Accounts.Agent`. Used to forbid access-management actions
  (adding/removing members, creating Agents, issuing/revoking keys) for
  Agent actors, per DESIGN.md's policies rule.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an agent"

  @impl true
  def match?(%Artifacts.Accounts.Agent{}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
