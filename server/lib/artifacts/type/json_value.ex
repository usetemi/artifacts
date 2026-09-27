defmodule Artifacts.Type.JSONValue do
  @moduledoc """
  Any JSON value, not only a map: a string, number, boolean, array, object,
  or `nil`. `StateEntry.value`, `Submission.payload`, and `Event.data` all
  use it — a state leaf, a submission payload, or an Event's pointer data
  may be a scalar or array, so `Ash.Type.Map`'s map-only cast would reject
  it.

  Stored the same way `:map` is (Postgres `jsonb`), but every callback is a
  pass-through: casting, loading, and dumping never coerce or reject the
  shape of the value. Whatever isn't valid JSON fails at the Postgrex
  encoding step, the same place a plain `:map` column always failed on a
  non-encodable value.
  """

  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(value, _constraints), do: {:ok, value}

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints), do: {:ok, value}

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints), do: {:ok, value}
end
