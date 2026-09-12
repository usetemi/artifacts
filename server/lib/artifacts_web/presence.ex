defmodule ArtifactsWeb.Presence do
  use Phoenix.Presence,
    otp_app: :artifacts,
    pubsub_server: Artifacts.PubSub
end
