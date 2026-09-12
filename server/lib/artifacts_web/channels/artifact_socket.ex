defmodule ArtifactsWeb.ArtifactSocket do
  use Phoenix.Socket

  channel "artifact:*", ArtifactsWeb.ArtifactChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
