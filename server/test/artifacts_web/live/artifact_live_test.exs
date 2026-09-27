defmodule ArtifactsWeb.ArtifactLiveTest do
  use ArtifactsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Publishing
  alias Artifacts.Publishing.Submission
  alias ArtifactsWeb.Presence

  setup %{conn: conn} do
    user = user_fixture!()
    artifact = artifact_fixture!(user, title: "Triage board")
    %{conn: log_in_user(conn, user), user: user, artifact: artifact}
  end

  test "renders the title, version, and the page frame", %{conn: conn, artifact: artifact} do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    assert has_element?(view, "h1", "Triage board")
    assert has_element?(view, ".chrome-meta", "v1")
    assert has_element?(view, "iframe#page")
    assert has_element?(view, "button#submit")
  end

  test "a non-member's artifact 404s", %{conn: conn, artifact: artifact} do
    other = user_fixture!()
    conn = log_in_user(conn, other)

    assert_error_sent 404, fn -> live(conn, ~p"/a/#{artifact.id}") end
  end

  test "an unknown artifact 404s", %{conn: conn} do
    assert_error_sent 404, fn -> live(conn, ~p"/a/missing") end
  end

  test "a new version mints a fresh token and pushes a new iframe src", %{
    conn: conn,
    artifact: artifact,
    user: user
  } do
    {:ok, view, html} = live(conn, ~p"/a/#{artifact.id}")
    assert [_, original_src] = Regex.run(~r/id="page"[^>]*src="([^"]+)"/, html)

    {:ok, _artifact2} = Publishing.publish(artifact, "<p>2</p>", nil, actor: user)

    assert render(view) =~ "v2"
    assert_push_event(view, "page:reload", %{src: new_src})
    assert new_src =~ ~r{/a/#{artifact.id}/page\?t=}
    refute new_src == original_src
  end

  test "submit with a note records a submission with the note as payload", %{
    conn: conn,
    artifact: artifact,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    view |> form("form.chrome-submit", %{"note" => "please review"}) |> render_submit()

    assert has_element?(view, "#submitted", "sent")
    assert [submission] = Ash.read!(Submission, actor: user)
    assert submission.payload == %{"note" => "please review"}
  end

  test "submit with a blank note records a submission with no payload", %{
    conn: conn,
    artifact: artifact,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    view |> form("form.chrome-submit", %{"note" => "   "}) |> render_submit()

    assert has_element?(view, "#submitted")
    assert [submission] = Ash.read!(Submission, actor: user)
    assert submission.payload == nil
  end

  test "rename changes the title", %{conn: conn, artifact: artifact} do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    view |> element("button", "Rename") |> render_click()
    view |> form("form.chrome-title-form", %{"title" => "New Title"}) |> render_submit()

    assert has_element?(view, "h1", "New Title")
  end

  test "archive hides the page and offers Unarchive; unarchive restores it", %{
    conn: conn,
    artifact: artifact
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")

    view |> element("button", "Archive") |> render_click()

    assert has_element?(view, ".badge-archived")
    refute has_element?(view, "iframe#page")
    assert has_element?(view, "button", "Unarchive")

    view |> element("button", "Unarchive") |> render_click()

    refute has_element?(view, ".badge-archived")
    assert has_element?(view, "iframe#page")
  end

  test "shows live Presence names, without tracking the chrome itself", %{
    conn: conn,
    artifact: artifact,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/a/#{artifact.id}")
    topic = "artifact:#{artifact.id}"
    :ok = Phoenix.PubSub.subscribe(Artifacts.PubSub, topic)

    assert has_element?(view, ".chrome-meta", "no one else here")

    {:ok, _ref} = Presence.track(self(), topic, user.id, %{name: user.name, meta: %{}})
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}

    assert render(view) =~ "1 viewer"
    assert Presence.list(topic) |> Map.keys() == [user.id]
  end
end
