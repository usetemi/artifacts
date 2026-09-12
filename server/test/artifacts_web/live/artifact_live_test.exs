defmodule ArtifactsWeb.ArtifactLiveTest do
  use ArtifactsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Artifacts.Store

  setup do
    {:ok, artifact} = Store.create(%{title: "Triage board", html: "<!doctype html><p>hi</p>"})
    %{artifact: artifact}
  end

  test "renders the title, version, and the page frame", %{conn: conn, artifact: artifact} do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    assert has_element?(view, "h1", "Triage board")
    assert has_element?(view, ".chrome-meta", "v1")
    assert has_element?(view, "iframe#page[src='/a/#{artifact.id}/page']")
    assert has_element?(view, "button#submit")
  end

  test "submit from the chrome records a submission attributed to the viewer", %{
    conn: conn,
    artifact: artifact
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    render_hook(view, "submit", %{"viewer_id" => "v1"})

    assert [%{viewer_id: "v1", payload: nil}] = Store.submissions(artifact.id)
    assert has_element?(view, "#submitted", "sent")
  end

  test "a new version updates the badge and tells the frame to reload", %{
    conn: conn,
    artifact: artifact
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    {:ok, 2} = Store.publish(artifact.id, "<p>2</p>")

    assert render(view) =~ "v2"
    assert_push_event view, "reload", %{}
  end

  test "unknown and archived artifacts are 404", %{conn: conn, artifact: artifact} do
    assert_raise ArtifactsWeb.NotFoundError, fn -> live(conn, ~p"/a/missing") end

    {:ok, _} = Store.archive(artifact.id)
    assert_raise ArtifactsWeb.NotFoundError, fn -> live(conn, ~p"/a/#{artifact.id}") end
  end

  test "submit after an archive records nothing", %{conn: conn, artifact: artifact} do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")
    {:ok, _} = Store.archive(artifact.id)

    render_hook(view, "submit", %{"viewer_id" => "v1"})

    assert Store.submissions(artifact.id) == []
    refute has_element?(view, "#submitted")
  end
end
