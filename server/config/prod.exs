import Config

config :artifacts, ArtifactsWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# TLS is the job of whatever fronts the host (Fly's proxy, a load
# balancer). The host itself speaks plain HTTP so a local Compose works
# without certificates, and never redirects.

config :logger, level: :info
