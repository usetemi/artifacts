defmodule ArtifactsWeb.ChannelCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import ArtifactsWeb.ChannelCase

      @endpoint ArtifactsWeb.Endpoint
    end
  end

  setup tags do
    Artifacts.DataCase.setup_sandbox(tags)
    :ok
  end
end
