defmodule ArtifactsWeb.SettingsLiveTest do
  use ArtifactsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Artifacts.AccountsFixtures

  require Ash.Query

  alias Artifacts.Accounts
  alias Artifacts.Accounts.Membership

  setup %{conn: conn} do
    user = user_fixture!()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "creates an Organization and switches to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html =
      view
      |> form("#create-organization-form", %{"name" => "New Co"})
      |> render_submit()

    assert html =~ "New Co"
    assert has_element?(view, "#org-switcher option[selected]", "New Co")
  end

  test "adds a member by email and removes them", %{conn: conn, user: user} do
    other = user_fixture!(email: "friend@usetemi.com")
    {:ok, view, _html} = live(conn, ~p"/settings")

    view |> form("#add-member-form", %{"email" => other.email}) |> render_submit()

    assert has_element?(view, "td", "friend@usetemi.com")

    membership =
      Membership
      |> Ash.read!(actor: user)
      |> Enum.find(&(&1.user_id == other.id))

    view |> element("#membership-#{membership.id} button", "Remove") |> render_click()

    refute has_element?(view, "td", "friend@usetemi.com")
  end

  test "adding an unknown email fails with a message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html =
      view
      |> form("#add-member-form", %{"email" => "nobody@usetemi.com"})
      |> render_submit()

    assert html =~ "no user with that email"
  end

  test "leaving is refused as the last member", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    [membership] = Ash.read!(Membership, actor: user)

    assert has_element?(
             view,
             "#membership-#{membership.id} button[disabled]",
             "Leave"
           )

    render_click(view, "leave", %{"id" => membership.id})

    # Still a member: the organization still shows in the switcher.
    assert has_element?(view, "#membership-#{membership.id}")
  end

  test "leaving succeeds when another member remains", %{conn: conn, user: user} do
    organization = personal_organization!(user)
    other = user_fixture!()
    {:ok, other_membership} = Accounts.add_member(organization.id, other.email, actor: user)

    conn = log_in_user(conn, other)
    {:ok, view, _html} = live(conn, ~p"/settings?org=#{organization.id}")

    render_click(view, "leave", %{"id" => other_membership.id})

    assert Ash.count!(Ash.Query.filter(Membership, id == ^other_membership.id),
             authorize?: false
           ) == 0
  end

  test "creates an Agent and issues and revokes its key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view |> form("#create-agent-form", %{"name" => "Pidgey"}) |> render_submit()
    assert has_element?(view, "h3", "Pidgey")

    html = view |> element("button", "Issue key") |> render_click()

    assert html =~ "arta_"
    assert html =~ "claude mcp add"
    assert has_element?(view, "#revealed-key")

    view |> element("button", "Revoke") |> render_click()

    assert has_element?(view, ".badge", "Revoked")
  end

  test "creates a Harness and revokes it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html =
      view
      |> form("#create-harness-form", %{"name" => "Victor's Claude Code"})
      |> render_submit()

    assert has_element?(view, "li", "Victor's Claude Code")
    assert html =~ "arth_"
    assert has_element?(view, "#revealed-key")

    view |> element("button", "Dismiss") |> render_click()
    refute has_element?(view, "#revealed-key")

    view |> element("li button", "Revoke") |> render_click()
    assert has_element?(view, ".badge", "Revoked")
  end

  test "a key is shown only right after creation, not on a later mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    view |> form("#create-harness-form", %{"name" => "Ephemeral"}) |> render_submit()
    assert has_element?(view, "#revealed-key")

    {:ok, fresh_view, _html} = live(conn, ~p"/settings")
    refute has_element?(fresh_view, "#revealed-key")
  end
end
