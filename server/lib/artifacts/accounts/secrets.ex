defmodule Artifacts.Accounts.Secrets do
  @moduledoc """
  `AshAuthentication.Secret` implementation for `Artifacts.Accounts.User`'s
  Google strategy and token signing secret. Every value is read from
  application config, which `config/runtime.exs` populates from environment
  variables.
  """

  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :strategies, :google, :client_id],
        Artifacts.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:artifacts, :google_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_secret],
        Artifacts.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:artifacts, :google_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :redirect_uri],
        Artifacts.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:artifacts, :google_redirect_uri)
  end

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Artifacts.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:artifacts, :token_signing_secret)
  end
end
