defmodule Artifacts.State do
  @moduledoc """
  Pure functions over an artifact's shared state.

  State is stored as leaves: a flat map from dotted path to JSON value.
  These functions turn leaves into the nested object pages see, and turn
  a requested op (`set` or `delete` at a path) into the exact rows to
  delete and write so the leaf set stays a tree: no path is ever both a
  leaf and a prefix of another leaf.

  The same rules run in the browser runtime, so a page applying an op
  locally and the host applying it to Postgres agree on the result.
  """

  @max_path_bytes 1000
  @max_value_bytes 256 * 1024

  @type path :: String.t()
  @type leaves :: %{path => term()}
  @type op :: %{op: :set, path: path, value: term()} | %{op: :delete, path: path}

  @doc "Builds the nested object from leaves. `\"a.b\" => 1` becomes `%{\"a\" => %{\"b\" => 1}}`."
  @spec expand(leaves) :: map()
  def expand(leaves) do
    leaves
    |> Enum.sort_by(fn {path, _value} -> path end)
    |> Enum.reduce(%{}, fn {path, value}, acc ->
      put_in_path(acc, String.split(path, "."), value)
    end)
  end

  defp put_in_path(_acc, [], value), do: value

  defp put_in_path(acc, [key | rest], value) when is_map(acc) do
    Map.put(acc, key, put_in_path(Map.get(acc, key, %{}), rest, value))
  end

  # A leaf sits where a subtree is being written: the leaf loses.
  defp put_in_path(_acc, keys, value), do: put_in_path(%{}, keys, value)

  @doc "The subtree at `path` inside an expanded object, or nil."
  @spec get(map(), path) :: term()
  def get(state, path) do
    Enum.reduce_while(String.split(path, "."), state, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _other -> {:halt, nil}
      end
    end)
  end

  @doc """
  Flattens a JSON value at `path` into leaves. A map with keys becomes
  one leaf per nested key; everything else (scalars, arrays, an empty
  map) is one leaf. `null` is absence: it writes no leaf, so a nested
  null clears that path the same way a top-level null does.
  """
  @spec flatten(path, term()) :: leaves
  def flatten(_path, nil), do: %{}

  def flatten(path, value) when is_map(value) and map_size(value) > 0 do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      Map.merge(acc, flatten(path <> "." <> to_string(key), nested))
    end)
  end

  def flatten(path, value), do: %{path => value}

  @doc """
  Validates and normalizes ops from a client or the CLI. Returns the ops
  with atom keys, or the first problem found.
  """
  @spec normalize_ops(term()) :: {:ok, [op]} | {:error, String.t()}
  def normalize_ops(ops) when is_list(ops) do
    ops
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      case normalize_op(raw) do
        {:ok, op} -> {:cont, {:ok, [op | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_ops(_other), do: {:error, "ops must be a list"}

  # A null value is a delete, so no row ever has to represent "null" and
  # every op that reaches storage or a page is one of two shapes.
  defp normalize_op(%{"op" => "set", "path" => path, "value" => nil}) do
    normalize_op(%{"op" => "delete", "path" => path})
  end

  defp normalize_op(%{"op" => "set", "path" => path, "value" => value}) do
    with :ok <- validate_path(path),
         :ok <- validate_value(value) do
      {:ok, %{op: :set, path: path, value: value}}
    end
  end

  defp normalize_op(%{"op" => "delete", "path" => path}) do
    with :ok <- validate_path(path) do
      {:ok, %{op: :delete, path: path}}
    end
  end

  defp normalize_op(%{op: :set, path: path, value: value}) do
    normalize_op(%{"op" => "set", "path" => path, "value" => value})
  end

  defp normalize_op(%{op: :delete, path: path}) do
    normalize_op(%{"op" => "delete", "path" => path})
  end

  defp normalize_op(_other),
    do: {:error, "each op is {op: set, path, value} or {op: delete, path}"}

  @doc "Checks a dotted path: non-empty segments, no whitespace, at most #{@max_path_bytes} bytes."
  @spec validate_path(term()) :: :ok | {:error, String.t()}
  def validate_path(path) when is_binary(path) do
    segments = String.split(path, ".")

    cond do
      byte_size(path) > @max_path_bytes -> {:error, "path longer than #{@max_path_bytes} bytes"}
      Enum.any?(segments, &(&1 == "")) -> {:error, "path has an empty segment"}
      String.match?(path, ~r/\s/) -> {:error, "path contains whitespace"}
      true -> :ok
    end
  end

  def validate_path(_other), do: {:error, "path must be a string"}

  defp validate_value(value) do
    if byte_size(Jason.encode!(value)) > @max_value_bytes do
      {:error, "value larger than #{@max_value_bytes} bytes"}
    else
      :ok
    end
  end

  @doc """
  Applies ops to leaves in memory. Used by tests and to compute the
  snapshot a submission records; the host applies the same rules in SQL.
  """
  @spec apply_ops(leaves, [op]) :: leaves
  def apply_ops(leaves, ops) do
    Enum.reduce(ops, leaves, &apply_op(&2, &1))
  end

  defp apply_op(leaves, %{op: :delete, path: path}) do
    remove_subtree(leaves, path)
  end

  defp apply_op(leaves, %{op: :set, path: path, value: value}) do
    leaves
    |> remove_subtree(path)
    |> Map.drop(ancestors(path))
    |> Map.merge(flatten(path, value))
  end

  defp remove_subtree(leaves, path) do
    prefix = path <> "."
    Map.reject(leaves, fn {key, _value} -> key == path or String.starts_with?(key, prefix) end)
  end

  @doc "Every proper prefix of a path: `\"a.b.c\"` gives `[\"a\", \"a.b\"]`."
  @spec ancestors(path) :: [path]
  def ancestors(path) do
    path
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.scan(fn segment, acc -> acc <> "." <> segment end)
  end
end
