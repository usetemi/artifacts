defmodule ArtifactsWeb.NotFoundError do
  @moduledoc "Raised by a LiveView for an unknown artifact so the endpoint renders a 404."

  defexception message: "not found", plug_status: 404
end
