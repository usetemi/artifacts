defmodule ArtifactsWeb.API.Errors do
  @moduledoc "The API's error responses: one JSON shape, `{\"error\": ...}`, per status."

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  def conflict(conn), do: conn |> put_status(:conflict) |> json(%{error: "conflict"})

  def quota(conn), do: conn |> put_status(:unprocessable_entity) |> json(%{error: "quota"})

  def unprocessable(conn, reason) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
  end
end
