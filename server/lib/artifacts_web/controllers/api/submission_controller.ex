defmodule ArtifactsWeb.API.SubmissionController do
  use ArtifactsWeb, :controller

  alias Artifacts.Store
  alias ArtifactsWeb.API.Errors

  # A single long-poll stays under every harness's command timeout; the
  # CLI loops when the agent asked to wait longer.
  @max_wait_seconds 100

  def create(conn, %{"id" => id} = params) do
    case Store.submit(id, params["payload"], params["viewer_id"]) do
      {:ok, submission} -> conn |> put_status(:created) |> json(submission_json(submission))
      {:error, :not_found} -> Errors.not_found(conn)
      {:error, :archived} -> Errors.archived(conn)
      {:error, :quota} -> Errors.quota(conn)
    end
  end

  @doc """
  Lists submissions after `since`. With `timeout`, the request blocks
  until one arrives or the timeout passes, answering 204 in the latter
  case; this is the long-poll behind the CLI's `wait`.
  """
  def index(conn, %{"id" => id} = params) do
    since = integer_param(params["since"], 0)

    with {:ok, _artifact} <- Store.get(id) do
      case params["timeout"] do
        nil ->
          json(conn, Enum.map(Store.submissions(id, since), &submission_json/1))

        timeout ->
          seconds = timeout |> integer_param(1) |> min(@max_wait_seconds)

          case Store.wait_for_submissions(id, since, seconds * 1000) do
            {:ok, submissions} -> json(conn, Enum.map(submissions, &submission_json/1))
            :timeout -> send_resp(conn, :no_content, "")
          end
      end
    else
      {:error, :not_found} -> Errors.not_found(conn)
    end
  end

  defp integer_param(nil, default), do: default

  defp integer_param(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _other -> default
    end
  end

  defp submission_json(submission) do
    %{
      id: submission.id,
      artifact_id: submission.artifact_id,
      version: submission.version,
      viewer_id: submission.viewer_id,
      state: submission.state,
      payload: submission.payload,
      inserted_at: submission.inserted_at
    }
  end
end
