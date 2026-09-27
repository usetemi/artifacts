defmodule Artifacts.Publishing.Errors do
  @moduledoc """
  Maps any error a `Artifacts.Publishing` action raises to one of a small,
  stable set of string codes (DESIGN.md "Content changes"). The channel's
  error replies, the Page API's rejections, and the MCP/HTTP error
  responses all read through this one function; nothing maps an error a
  second way.
  """

  alias Artifacts.Publishing.Errors.{Archived, Conflict, Quota}

  @codes ~w(conflict archived not_found forbidden quota invalid unknown)

  @typedoc ~s(One of "conflict", "archived", "not_found", "forbidden", "quota", "invalid", "unknown".)
  @type code :: String.t()

  @doc """
  Resolves an `Ash.Error.t()` (or a bare wrapped error, or a list of them)
  to its stable code. An `Ash.Error.Invalid` wrapping several errors picks
  the most specific code any of them resolves to, so one `conflict` among
  several `invalid` field errors still surfaces as `"conflict"`.
  """
  @spec to_code(term()) :: code()
  def to_code(%Ash.Error.Invalid{errors: errors}) when errors not in [nil, []] do
    pick(errors)
  end

  def to_code(%Ash.Error.Forbidden{}), do: "forbidden"
  def to_code(%Conflict{}), do: "conflict"
  def to_code(%Archived{}), do: "archived"
  def to_code(%Quota{}), do: "quota"
  def to_code(%Ash.Error.Query.NotFound{}), do: "not_found"
  def to_code(%Ash.Error.Invalid{}), do: "invalid"
  def to_code(%Ash.Error.Unknown{}), do: "unknown"
  def to_code(%Ash.Error.Framework{}), do: "unknown"
  def to_code(errors) when is_list(errors) and errors != [], do: pick(errors)
  # Any other Ash/Splode error not named above (a field-level InvalidAttribute
  # or InvalidArgument nested inside an Ash.Error.Invalid, for example) still
  # carries its Splode error class; fall back to that rather than "unknown".
  def to_code(%{class: :invalid}), do: "invalid"
  def to_code(%{class: :forbidden}), do: "forbidden"
  def to_code(_other), do: "unknown"

  defp pick(errors) do
    errors
    |> Enum.map(&to_code/1)
    |> Enum.min_by(fn code -> Enum.find_index(@codes, &(&1 == code)) end)
  end
end
