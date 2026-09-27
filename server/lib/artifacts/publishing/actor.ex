defmodule Artifacts.Publishing.Actor do
  @moduledoc """
  Turns a live actor (a `User` or an `Agent`) plus the shared Harness
  context into the two shapes DESIGN.md's "Actor columns" and "Actor
  reference" name.

  `columns/2` is what every child create (`Version`, `StateEntry`,
  `Submission`, `Event`) uses to fill its actor attributes from the parent
  `Artifact` action's `after_action`. `ref/2` is what `ChannelNotifier` and
  `Artifact.history`'s replay of a stored actor put on the wire: `{type,
  id, name, harness}`, where `harness` is the Harness's own name when a
  User acted through one, else `nil` — an Agent's reference always carries
  `harness: nil`.

  `shared` is the `context[:shared]` map a caller who acted through a
  Harness carries (`%{harness_id: id, harness_name: name}`), or `nil`/`%{}`
  for a direct User or an Agent.
  """

  alias Artifacts.Accounts.{Agent, User}

  @type shared ::
          %{optional(:harness_id) => String.t(), optional(:harness_name) => String.t()} | nil

  @type columns :: %{
          user_id: String.t() | nil,
          agent_id: String.t() | nil,
          harness_id: String.t() | nil
        }

  @type ref :: %{type: String.t(), id: String.t(), name: String.t(), harness: String.t() | nil}

  @spec columns(actor :: term(), shared()) :: columns()
  def columns(%User{id: id}, shared) do
    %{user_id: id, agent_id: nil, harness_id: get(shared, :harness_id)}
  end

  def columns(%Agent{id: id}, _shared) do
    %{user_id: nil, agent_id: id, harness_id: nil}
  end

  @spec ref(actor :: term(), shared()) :: ref()
  def ref(%User{id: id, name: name}, shared) do
    %{type: "user", id: id, name: name, harness: get(shared, :harness_name)}
  end

  def ref(%Agent{id: id, name: name}, _shared) do
    %{type: "agent", id: id, name: name, harness: nil}
  end

  defp get(nil, _key), do: nil
  defp get(shared, key), do: Map.get(shared, key)
end
