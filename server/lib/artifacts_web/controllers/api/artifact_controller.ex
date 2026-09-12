defmodule ArtifactsWeb.API.ArtifactController do
  use ArtifactsWeb, :controller

  alias Artifacts.Store
  alias ArtifactsWeb.API.Errors

  def index(conn, _params) do
    json(conn, Enum.map(Store.list(), &artifact_json/1))
  end

  def create(conn, %{"title" => title, "html" => html}) do
    case Store.create(%{title: title, html: html}) do
      {:ok, artifact} -> conn |> put_status(:created) |> json(artifact_json(artifact))
      {:error, reason} -> Errors.unprocessable(conn, reason)
    end
  end

  def create(conn, _params), do: Errors.unprocessable(conn, "title and html are required")

  def show(conn, %{"id" => id}) do
    case Store.get(id) do
      {:ok, artifact} -> json(conn, artifact_json(artifact))
      {:error, :not_found} -> Errors.not_found(conn)
    end
  end

  def update(conn, %{"id" => id, "html" => html} = params) do
    opts =
      Enum.reject([title: params["title"], if_version: params["if_version"]], fn {_key, value} ->
        is_nil(value)
      end)

    case Store.publish(id, html, opts) do
      {:ok, number} -> json(conn, %{id: id, version: number, url: page_url(id)})
      {:error, :not_found} -> Errors.not_found(conn)
      {:error, :archived} -> Errors.archived(conn)
      {:error, :conflict} -> Errors.conflict(conn)
      {:error, reason} -> Errors.unprocessable(conn, reason)
    end
  end

  def update(conn, _params), do: Errors.unprocessable(conn, "html is required")

  def archive(conn, %{"id" => id}) do
    case Store.archive(id) do
      {:ok, artifact} -> json(conn, artifact_json(artifact))
      {:error, :not_found} -> Errors.not_found(conn)
    end
  end

  def versions(conn, %{"id" => id}) do
    case Store.get(id) do
      {:ok, _artifact} -> json(conn, Store.versions(id))
      {:error, :not_found} -> Errors.not_found(conn)
    end
  end

  def version(conn, %{"id" => id, "number" => "current"}) do
    respond_version(conn, Store.current_version(id))
  end

  def version(conn, %{"id" => id, "number" => number}) do
    case Integer.parse(number) do
      {n, ""} when n > 0 -> respond_version(conn, Store.get_version(id, n))
      _other -> Errors.not_found(conn)
    end
  end

  defp respond_version(conn, {:ok, version}) do
    json(conn, %{
      number: version.number,
      published_by: version.published_by,
      inserted_at: version.inserted_at,
      html: version.html
    })
  end

  defp respond_version(conn, {:error, :not_found}), do: Errors.not_found(conn)

  defp artifact_json(artifact) do
    %{
      id: artifact.id,
      title: artifact.title,
      version: artifact.current_version,
      url: page_url(artifact.id),
      archived_at: artifact.archived_at,
      inserted_at: artifact.inserted_at,
      updated_at: artifact.updated_at
    }
  end

  defp page_url(id), do: url(~p"/a/#{id}")
end
