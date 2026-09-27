defmodule ArtifactsWeb.AuthOverrides do
  @moduledoc """
  Styles the sign-in page with the app's hand-written CSS (DESIGN.md "Web
  app"): no Tailwind, no daisyUI. Only `User`'s `google` strategy is
  configured, so `AshAuthentication.Phoenix.Components.SignIn` renders
  exactly one `Components.OAuth2` link and nothing else
  (`notes/ash_authentication.md §5.1`); the sign-out confirmation page keeps
  `AshAuthentication.Phoenix.Overrides.Default`'s classes, which are inert
  without Tailwind but otherwise harmless.
  """

  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{Components, SignInLive}

  override SignInLive do
    set(:root_class, "auth-page")
  end

  override Components.SignIn do
    set(:root_class, "auth-card")
    set(:show_banner, false)
    set(:strategy_class, "auth-strategy")
    set(:authentication_error_container_class, "auth-error")
    set(:authentication_error_text_class, "auth-error-text")
  end

  override Components.OAuth2 do
    set(:root_class, "auth-oauth")
    set(:link_class, "btn btn-google")
    set(:icon_class, "auth-icon")
  end
end
