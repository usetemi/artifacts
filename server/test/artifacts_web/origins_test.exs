defmodule ArtifactsWeb.OriginsTest do
  use ExUnit.Case, async: true

  alias ArtifactsWeb.Origins

  # Matches config/test.exs's app_host "localhost" and content_host
  # "127.0.0.1", and the port config/runtime.exs derives from $PORT
  # (unset here, so its "4000" default) — not test.exs's own `http:
  # [port: 4002]`, since runtime.exs's unconditional `http: [port: ...]`
  # loads after it and wins.
  @app_origin "http://localhost:4000"
  @content_origin "http://127.0.0.1:4000"

  test "app_origin/0 and content_origin/0 carry the configured hosts and port" do
    assert Origins.app_origin() == @app_origin
    assert Origins.content_origin() == @content_origin
  end

  test "socket_url/0 is the content origin's ws URL at /socket" do
    assert Origins.socket_url() == "ws://127.0.0.1:4000/socket"
  end

  test "app_origin?/1 matches only the app origin" do
    assert Origins.app_origin?(URI.parse(@app_origin))
    refute Origins.app_origin?(URI.parse(@content_origin))
    refute Origins.app_origin?(URI.parse("http://evil.example.com"))
  end

  test "content_origin?/1 matches only the content origin" do
    assert Origins.content_origin?(URI.parse(@content_origin))
    refute Origins.content_origin?(URI.parse(@app_origin))
    refute Origins.content_origin?(URI.parse("http://evil.example.com"))
  end
end
