import Config

config :artifacts,
  app_host: "localhost",
  content_host: "127.0.0.1",
  token_signing_secret: "test_only_signing_secret_do_not_use_in_production_0000",
  # Never dials out in tests; just lets the Google strategy's config
  # resolve, so a callback with no prior session fails on that instead of
  # on a missing secret.
  google_client_id: "test-google-client-id",
  google_client_secret: "test-google-client-secret",
  google_redirect_uri: "http://localhost:4002/auth/user/google/callback"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :artifacts, Artifacts.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "artifacts_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :artifacts, ArtifactsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SdI/2ZuCaGr8Q9XjvRkon1YVExEEZops9pBNUVyRRq5G8m4Dfd4XWz738fHXg2XL",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
