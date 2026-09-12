defmodule ArtifactsWeb.API.HistoryController do
  use ArtifactsWeb, :controller

  alias Artifacts.Store
  alias ArtifactsWeb.API.Errors

  @doc """
  Streams an artifact's history as NDJSON, oldest first, one event per
  line. Chunked, so a long history never has to fit in memory on either
  side: the host pages through the events and a client reads lines as
  they arrive.
  """
  def index(conn, %{"id" => id}) do
    case Store.get(id) do
      {:ok, _artifact} ->
        conn
        |> put_resp_content_type("application/x-ndjson")
        |> send_chunked(200)
        |> stream_events(id, 0)

      {:error, :not_found} ->
        Errors.not_found(conn)
    end
  end

  defp stream_events(conn, id, since) do
    case Store.history(id, since) do
      [] ->
        conn

      events ->
        lines = Enum.map_join(events, &(Jason.encode!(&1) <> "\n"))

        case chunk(conn, lines) do
          {:ok, conn} -> stream_events(conn, id, List.last(events).id)
          {:error, _closed} -> conn
        end
    end
  end
end
