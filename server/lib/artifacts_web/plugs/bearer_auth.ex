defmodule ArtifactsWeb.Plugs.BearerAuth do
  @moduledoc """
  Resolves `Authorization: Bearer <prefix>_...` by prefix: `arth` signs in a
  `Artifacts.Accounts.User` (a Harness key), `arta` signs in a
  `Artifacts.Accounts.Agent` (an Agent key). Either branch delegates to
  `AshAuthentication.Strategy.ApiKey.Plug`, so it gets that library's own
  key-shape validation, timing-safe comparison, and error-response
  content-negotiation for free.

  On a successful Harness-backed User sign-in, the resolved Harness's id and
  name are copied into the shared Ash context via `Ash.PlugHelpers.
  update_context/2` (never `set_context/2`, which would replace the whole
  context map) so every downstream action can record `harness_id` alongside
  `user_id`, per DESIGN.md's actor-columns rule.

  Mounted in the `:api` and `:mcp` router pipelines, after
  `ArtifactsWeb.Plugs.RequireHost, :app`.
  """

  @behaviour Plug

  alias AshAuthentication.Strategy.ApiKey.Plug, as: ApiKeyPlug

  @impl true
  def init(_opts) do
    %{
      # `strategy:` is omitted: each resource has exactly one `api_key`
      # strategy, and `ApiKeyPlug.init/1` auto-resolves it in that case.
      "arth" => ApiKeyPlug.init(resource: Artifacts.Accounts.User, assign: :current_user),
      "arta" => ApiKeyPlug.init(resource: Artifacts.Accounts.Agent, assign: :current_agent)
    }
  end

  @impl true
  def call(conn, config_by_prefix) do
    case bearer_prefix(conn) do
      nil ->
        ApiKeyPlug.on_error(conn, :missing_api_key)

      prefix ->
        case Map.fetch(config_by_prefix, prefix) do
          {:ok, config} -> conn |> ApiKeyPlug.call(config) |> record_harness_context()
          :error -> ApiKeyPlug.on_error(conn, :invalid_api_key)
        end
    end
  end

  defp bearer_prefix(conn) do
    with [header] <- Plug.Conn.get_req_header(conn, "authorization"),
         "Bearer " <> key <- header,
         [prefix | _] <- String.split(key, "_", parts: 2) do
      prefix
    else
      _ -> nil
    end
  end

  defp record_harness_context(%Plug.Conn{halted: true} = conn), do: conn

  defp record_harness_context(
         %Plug.Conn{
           assigns: %{
             current_user: %{__metadata__: %{api_key: %Artifacts.Accounts.Harness{} = harness}}
           }
         } = conn
       ) do
    Ash.PlugHelpers.update_context(conn, fn context ->
      Map.put(context || %{}, :shared, %{harness_id: harness.id, harness_name: harness.name})
    end)
  end

  defp record_harness_context(conn), do: conn
end
