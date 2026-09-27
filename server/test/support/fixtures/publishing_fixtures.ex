defmodule Artifacts.PublishingFixtures do
  @moduledoc """
  Test fixtures for `Artifacts.Publishing`, built through the real actions
  so a fixture exercises the same changes and policies production code
  does.
  """

  alias Artifacts.Publishing

  @html "<!doctype html><html><body><h1>Hi</h1></body></html>"

  def html, do: @html

  @doc "Creates an Artifact as `actor`, in `actor`'s own default Organization unless :organization_id is given."
  def artifact_fixture!(actor, opts \\ []) do
    title = Keyword.get(opts, :title, "Board #{System.unique_integer([:positive])}")
    html = Keyword.get(opts, :html, @html)

    extra_params =
      opts
      |> Keyword.take([:organization_id])
      |> Map.new()

    Publishing.create_artifact!(title, html, extra_params, actor: actor)
  end
end
