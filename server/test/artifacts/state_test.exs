defmodule Artifacts.StateTest do
  use ExUnit.Case, async: true

  alias Artifacts.State

  @fixture Path.expand("../fixtures/state_cases.json", __DIR__)

  for %{"name" => name} = case <- Jason.decode!(File.read!(@fixture))["cases"] do
    @case case
    test name do
      %{"leaves" => leaves, "ops" => raw_ops, "expected" => expected, "expanded" => expanded} =
        @case

      {:ok, ops} = State.normalize_ops(raw_ops)

      result = State.apply_ops(leaves, ops)

      assert result == expected
      assert State.expand(result) == expanded
    end
  end

  test "get reads a subtree of an expanded object" do
    state = State.expand(%{"a.b" => 1, "a.c" => 2})

    assert State.get(state, "a") == %{"b" => 1, "c" => 2}
    assert State.get(state, "a.b") == 1
    assert State.get(state, "a.b.c") == nil
    assert State.get(state, "missing") == nil
  end

  test "normalize_ops rejects malformed input" do
    assert {:error, "ops must be a list"} = State.normalize_ops(%{})
    assert {:error, _} = State.normalize_ops([%{"op" => "rename", "path" => "a"}])

    assert {:error, "path has an empty segment"} =
             State.normalize_ops([%{"op" => "delete", "path" => "a..b"}])

    assert {:error, "path has an empty segment"} =
             State.normalize_ops([%{"op" => "delete", "path" => ".a"}])

    assert {:error, "path contains whitespace"} =
             State.normalize_ops([%{"op" => "set", "path" => "a b", "value" => 1}])

    assert {:error, "path must be a string"} =
             State.normalize_ops([%{"op" => "delete", "path" => 3}])

    big = String.duplicate("x", 256 * 1024 + 1)

    assert {:error, "value larger than " <> _} =
             State.normalize_ops([%{"op" => "set", "path" => "a", "value" => big}])
  end

  test "normalize_ops accepts atom-keyed ops from the host" do
    assert {:ok, [%{op: :set, path: "a", value: 1}, %{op: :delete, path: "b"}]} =
             State.normalize_ops([%{op: :set, path: "a", value: 1}, %{op: :delete, path: "b"}])
  end

  test "ancestors lists every proper prefix" do
    assert State.ancestors("a") == []
    assert State.ancestors("a.b.c") == ["a", "a.b"]
  end
end
