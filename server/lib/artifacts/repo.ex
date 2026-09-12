defmodule Artifacts.Repo do
  use Ecto.Repo,
    otp_app: :artifacts,
    adapter: Ecto.Adapters.Postgres
end
