defmodule ArtifactsWeb.ArtifactsLiveTest do
  use ArtifactsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Accounts
  alias Artifacts.Publishing

  setup %{conn: conn} do
    user = user_fixture!()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "lists the open Artifacts of the User's Personal Organization by default", %{
    conn: conn,
    user: user
  } do
    artifact = artifact_fixture!(user, title: "Board one")

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Board one"
    assert has_element?(view, ".page-header-subtitle", personal_organization!(user).name)
    refute has_element?(view, ".empty-state")
    assert html =~ artifact.title

    # The nav's sign-out link must issue a DELETE (the route sign_out_route
    # wires to AuthController.sign_out), not a plain GET navigation to the
    # confirmation page.
    assert has_element?(view, "a[href='/sign-out'][data-method='delete']", "Sign out")
  end

  test "the archived filter hides open artifacts and shows archived ones", %{
    conn: conn,
    user: user
  } do
    open = artifact_fixture!(user, title: "Still open")
    archived = artifact_fixture!(user, title: "Put away")
    {:ok, _} = Publishing.archive(archived, actor: user)

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ open.title
    refute html =~ archived.title

    html = view |> element(".list-toolbar a", "Show archived") |> render_click()

    assert html =~ archived.title
    refute html =~ open.title
  end

  test "switching Organizations changes the list", %{conn: conn, user: user} do
    owner = user_fixture!()
    other_org = organization_fixture!(owner, name: "Team Org")
    {:ok, _membership} = Accounts.add_member(other_org.id, user.email, actor: owner)

    personal_artifact = artifact_fixture!(user, title: "Only Mine Board")
    team_artifact = artifact_fixture!(owner, organization_id: other_org.id, title: "Team Board")

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ personal_artifact.title
    refute html =~ team_artifact.title

    html =
      view
      |> form("#org-switcher", %{"org" => other_org.id})
      |> render_change()

    assert html =~ team_artifact.title
    refute html =~ personal_artifact.title
  end

  test "a non-member org id in the URL falls back to an accessible Organization", %{
    conn: conn,
    user: user
  } do
    owner = user_fixture!()
    other_org = organization_fixture!(owner)
    _not_visible = artifact_fixture!(owner, organization_id: other_org.id, title: "Not yours")

    # The switcher itself can't select an Organization the user doesn't
    # belong to (it isn't rendered as an option), so this exercises the
    # server-side fallback directly, as a hand-typed or bookmarked URL would.
    {:ok, view, html} = live(conn, ~p"/?org=#{other_org.id}")

    refute html =~ "Not yours"
    assert has_element?(view, ".page-header-subtitle", personal_organization!(user).name)
  end
end
