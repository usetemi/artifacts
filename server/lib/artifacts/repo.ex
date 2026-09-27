defmodule Artifacts.Repo do
  use AshPostgres.Repo, otp_app: :artifacts

  def installed_extensions do
    ["uuid-ossp", "citext", "ash-functions"]
  end

  def min_pg_version do
    %Version{major: 17, minor: 0, patch: 0}
  end
end
