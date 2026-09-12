defmodule Artifacts.JSON do
  @moduledoc """
  An Ecto type for a `jsonb` column that holds any JSON value, not only
  an object. Ecto's built-in `:map` type rejects scalars and arrays at
  the cast step; state values and submission payloads are arbitrary JSON.
  """

  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(value), do: {:ok, value}

  @impl true
  def load(value), do: {:ok, value}

  @impl true
  def dump(value), do: {:ok, value}
end
