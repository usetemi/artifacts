defmodule ArtifactsWeb.ArtifactChannelTest do
  use ArtifactsWeb.ChannelCase, async: false

  alias Artifacts.Store
  alias ArtifactsWeb.{ArtifactChannel, ArtifactSocket}

  @html "<!doctype html><p>hi</p>"

  setup do
    {:ok, artifact} = Store.create(%{title: "Board", html: @html})

    {:ok, _} =
      Store.apply_ops(artifact.id, [%{"op" => "set", "path" => "a.b", "value" => 1}], "agent")

    %{artifact: artifact}
  end

  defp join_as(artifact, viewer_id) do
    {:ok, socket} = connect(ArtifactSocket, %{})

    subscribe_and_join(socket, ArtifactChannel, "artifact:" <> artifact.id, %{
      "viewer_id" => viewer_id
    })
  end

  test "join replies with the version and the flat state, then presence", %{artifact: artifact} do
    assert {:ok, %{version: 1, state: %{"a.b" => 1}}, _socket} = join_as(artifact, "v1")
    assert_push "presence_state", %{"v1" => %{metas: [%{meta: %{}}]}}
  end

  test "join needs an open artifact and a viewer id", %{artifact: artifact} do
    {:ok, socket} = connect(ArtifactSocket, %{})

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, ArtifactChannel, "artifact:missing", %{
               "viewer_id" => "v1"
             })

    assert {:error, %{reason: "viewer_id must be" <> _}} =
             subscribe_and_join(socket, ArtifactChannel, "artifact:" <> artifact.id, %{})

    {:ok, _} = Store.archive(artifact.id)
    assert {:error, %{reason: "archived"}} = join_as(artifact, "v1")
  end

  test "state ops persist, reply ok, and reach every viewer with attribution", %{
    artifact: artifact
  } do
    {:ok, _reply, writer} = join_as(artifact, "v1")
    {:ok, _reply, _reader} = join_as(artifact, "v2")

    ref =
      push(writer, "state:ops", %{"ops" => [%{"op" => "set", "path" => "a.c", "value" => "x"}]})

    assert_reply ref, :ok

    assert_push "state:ops", %{ops: [%{op: :set, path: "a.c", value: "x"}], by: "viewer:v1"}
    assert Store.leaves(artifact.id) == %{"a.b" => 1, "a.c" => "x"}

    bad =
      push(writer, "state:ops", %{"ops" => [%{"op" => "set", "path" => "a..c", "value" => 1}]})

    assert_reply bad, :error, %{reason: "path has an empty segment"}
  end

  test "agent writes through the store are pushed to pages", %{artifact: artifact} do
    {:ok, _reply, _socket} = join_as(artifact, "v1")
    {:ok, _ops} = Store.apply_ops(artifact.id, [%{"op" => "delete", "path" => "a"}], "agent")

    assert_push "state:ops", %{ops: [%{op: :delete, path: "a"}], by: "agent"}
  end

  test "presence updates merge meta", %{artifact: artifact} do
    {:ok, _reply, socket} = join_as(artifact, "v1")
    assert_push "presence_state", _state

    ref = push(socket, "presence:update", %{"meta" => %{"cursor" => [1, 2]}})
    assert_reply ref, :ok
    assert_push "presence_diff", %{joins: %{"v1" => %{metas: [%{meta: %{"cursor" => [1, 2]}}]}}}
  end

  test "broadcast reaches the other viewers, not the sender", %{artifact: artifact} do
    {:ok, _reply, sender} = join_as(artifact, "v1")
    {:ok, _reply, _other} = join_as(artifact, "v2")

    push(sender, "broadcast", %{"topic" => "pointer", "data" => %{"x" => 1}})

    assert_push "broadcast", %{
      topic: "pointer",
      data: %{"x" => 1},
      from: %{viewer: %{id: "v1"}}
    }
  end

  test "submit records the viewer, the state, and the payload", %{artifact: artifact} do
    {:ok, _reply, socket} = join_as(artifact, "v1")

    ref = push(socket, "submit", %{"payload" => %{"choice" => "B"}})
    assert_reply ref, :ok, %{id: id}
    assert_push "submission", %{id: ^id, viewer_id: "v1"}

    assert [%{viewer_id: "v1", state: %{"a" => %{"b" => 1}}, payload: %{"choice" => "B"}}] =
             Store.submissions(artifact.id)
  end

  test "publish from a page is compare-and-set on the version", %{artifact: artifact} do
    {:ok, _reply, socket} = join_as(artifact, "v1")

    ref = push(socket, "publish", %{"html" => "<p>2</p>", "if_version" => 1})
    assert_reply ref, :ok, %{version: 2}
    assert_push "version", %{version: 2, by: "viewer:v1"}

    stale = push(socket, "publish", %{"html" => "<p>late</p>", "if_version" => 1})
    assert_reply stale, :error, %{reason: "conflict"}
    assert {:ok, %{html: "<p>2</p>"}} = Store.current_version(artifact.id)
  end

  test "an open page learns of an archive on its next write", %{artifact: artifact} do
    {:ok, _reply, socket} = join_as(artifact, "v1")
    {:ok, _} = Store.archive(artifact.id)

    ops = push(socket, "state:ops", %{"ops" => [%{"op" => "set", "path" => "z", "value" => 1}]})
    assert_reply ops, :error, %{reason: "archived"}

    submit = push(socket, "submit", %{"payload" => nil})
    assert_reply submit, :error, %{reason: "archived"}

    publish = push(socket, "publish", %{"html" => "<p>2</p>", "if_version" => 1})
    assert_reply publish, :error, %{reason: "archived"}

    assert Store.leaves(artifact.id) == %{"a.b" => 1}
  end
end
