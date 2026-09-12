defmodule ArtifactsWeb.API.StateController do
  use ArtifactsWeb, :controller

  alias Artifacts.{State, Store}
  alias ArtifactsWeb.API.Errors

  def show(conn, %{"id" => id} = params) do
    case Store.get(id) do
      {:ok, _artifact} ->
        state = Store.state(id)

        case params["path"] do
          nil -> json(conn, state)
          path -> json(conn, State.get(state, path))
        end

      {:error, :not_found} ->
        Errors.not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "ops" => ops}) do
    case Store.apply_ops(id, ops, Store.agent()) do
      {:ok, applied} -> json(conn, %{applied: applied})
      {:error, :not_found} -> Errors.not_found(conn)
      {:error, :quota} -> Errors.quota(conn)
      {:error, reason} -> Errors.unprocessable(conn, reason)
    end
  end

  def update(conn, _params), do: Errors.unprocessable(conn, "ops is required")
end
