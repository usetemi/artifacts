defmodule Artifacts.Guide do
  @moduledoc """
  The agent guide, served over MCP so a connected Harness or Agent needs no
  separate skill install. `skills/artifacts/SKILL.md` stays the one source:
  it is embedded here at compile time (the release image copies it to the
  same relative path), `get_guide` returns its body, and `instructions/1`
  is the short version every MCP client receives on `initialize`.
  """

  @path Path.expand("../../../skills/artifacts/SKILL.md", __DIR__)
  @external_resource @path

  @text @path
        |> File.read!()
        |> String.replace(~r/\A---\n.*?\n---\n+/s, "")

  @doc "SKILL.md without its front matter."
  def text, do: @text

  @doc "The MCP `initialize` instructions; kept under 2 KB so a client that truncates instructions keeps all of it."
  def instructions(_mcp_opts \\ []) do
    """
    Artifacts publishes interactive HTML pages that people open in a browser, change, and hand back with Submit. Call get_guide once before your first publish_artifact: it documents the page API (window.artifact), the CSP, the caps, and a complete example page.

    The loop:
    1. publish_artifact with the HTML (omit artifact_id to create). Note the id and Version.
    2. Share #{ArtifactsWeb.Origins.app_origin()}/a/<id>.
    3. wait for a Submission. It blocks up to 50 seconds and returns [] on timeout; call it again with since set to the last Submission id you saw. Never poll.
    4. get_state (and history if the path there matters), act, then publish_artifact again with the artifact_id and if_version set to the Version you last saw.

    Every failure is one of: conflict (stale if_version: re-read, fold your change in, retry), archived, not_found, forbidden, quota, invalid. Nothing is deleted; archive_artifact closes an Artifact. Anyone in the Artifact's Organization can view and change it, so put nothing into a page that Organization should not see.
    """
  end
end
