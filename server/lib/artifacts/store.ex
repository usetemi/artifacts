defmodule Artifacts.Store do
  @moduledoc """
  Everything durable about artifacts: create, publish versions, read and
  write shared state, record submissions, and wait for them.

  Every write commits to Postgres first and then broadcasts on the
  artifact's PubSub topic (`topic/1`), so channels, the chrome, and a
  waiting `wait` request all learn about it the same way:

    * `{:state_ops, ops, by}` after `apply_ops/3`
    * `{:version, number, by}` after `create/1` and `publish/3`
    * `{:submission, submission}` after `submit/3`
  """

  import Ecto.Query

  alias Artifacts.{Artifact, Repo, State, StateEntry, Submission, Version}

  @max_html_bytes 16 * 1024 * 1024
  @max_state_rows 10_000
  @max_submissions 10_000

  @type by :: String.t()

  @spec topic(String.t()) :: String.t()
  def topic(artifact_id), do: "artifact:" <> artifact_id

  @doc "Attribution for a write from the CLI."
  @spec agent() :: by
  def agent, do: "agent"

  @doc "Attribution for a write from a page."
  @spec viewer(String.t()) :: by
  def viewer(viewer_id), do: "viewer:" <> viewer_id

  ## Artifacts and versions

  @spec create(%{title: String.t(), html: String.t()}, by) ::
          {:ok, Artifact.t()} | {:error, String.t()}
  def create(%{title: title, html: html}, by \\ agent()) do
    with :ok <- validate_html(html),
         :ok <- validate_title(title) do
      id = generate_id()
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        artifact =
          Repo.insert!(%Artifact{
            id: id,
            title: title,
            current_version: 1,
            inserted_at: now,
            updated_at: now
          })

        Repo.insert!(%Version{
          artifact_id: id,
          number: 1,
          html: html,
          published_by: by,
          inserted_at: now
        })

        artifact
      end)
      |> case do
        {:ok, artifact} ->
          broadcast(id, {:version, 1, by})
          {:ok, artifact}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  @spec get(String.t()) :: {:ok, Artifact.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Artifact, id) do
      nil -> {:error, :not_found}
      artifact -> {:ok, artifact}
    end
  end

  @spec list() :: [Artifact.t()]
  def list do
    Repo.all(from a in Artifact, order_by: [desc: a.updated_at])
  end

  @doc """
  Publishes a new version. `opts` may carry `:title` and `:if_version`;
  with `:if_version` the publish only succeeds when it is the current
  version, which is how two writers avoid overwriting each other.
  """
  @spec publish(String.t(), String.t(), keyword()) ::
          {:ok, pos_integer()} | {:error, :not_found | :conflict | String.t()}
  def publish(id, html, opts \\ []) do
    by = Keyword.get(opts, :by, agent())

    with :ok <- validate_html(html),
         :ok <- validate_optional_title(opts[:title]) do
      Repo.transaction(fn ->
        case Repo.one(from a in Artifact, where: a.id == ^id, lock: "FOR UPDATE") do
          nil ->
            Repo.rollback(:not_found)

          %Artifact{current_version: current} = artifact ->
            expected = Keyword.get(opts, :if_version, current)

            if expected != current do
              Repo.rollback(:conflict)
            else
              number = current + 1
              now = DateTime.utc_now()

              Repo.insert!(%Version{
                artifact_id: id,
                number: number,
                html: html,
                published_by: by,
                inserted_at: now
              })

              artifact
              |> Ecto.Changeset.change(
                current_version: number,
                title: Keyword.get(opts, :title, artifact.title),
                updated_at: now
              )
              |> Repo.update!()

              number
            end
        end
      end)
      |> case do
        {:ok, number} ->
          broadcast(id, {:version, number, by})
          {:ok, number}

        {:error, :not_found} ->
          {:error, :not_found}

        {:error, :conflict} ->
          {:error, :conflict}
      end
    end
  end

  @spec versions(String.t()) :: [
          %{number: pos_integer(), published_by: by, inserted_at: DateTime.t()}
        ]
  def versions(id) do
    Repo.all(
      from v in Version,
        where: v.artifact_id == ^id,
        order_by: [asc: v.number],
        select: %{number: v.number, published_by: v.published_by, inserted_at: v.inserted_at}
    )
  end

  @spec get_version(String.t(), pos_integer()) :: {:ok, Version.t()} | {:error, :not_found}
  def get_version(id, number) do
    case Repo.get_by(Version, artifact_id: id, number: number) do
      nil -> {:error, :not_found}
      version -> {:ok, version}
    end
  end

  @doc "The artifact's current version, or not_found when it has none."
  @spec current_version(String.t()) :: {:ok, Version.t()} | {:error, :not_found}
  def current_version(id) do
    with {:ok, artifact} <- get(id) do
      get_version(id, artifact.current_version)
    end
  end

  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id) do
    case Repo.delete_all(from a in Artifact, where: a.id == ^id) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  ## State

  @doc "The flat leaves of an artifact's state."
  @spec leaves(String.t()) :: State.leaves()
  def leaves(id) do
    Repo.all(from e in StateEntry, where: e.artifact_id == ^id, select: {e.path, e.value})
    |> Map.new()
  end

  @doc "The nested state object."
  @spec state(String.t()) :: map()
  def state(id), do: id |> leaves() |> State.expand()

  @doc """
  Applies ops in one transaction and broadcasts them. Returns the
  normalized ops so a caller can echo them.
  """
  @spec apply_ops(String.t(), term(), by) ::
          {:ok, [State.op()]} | {:error, :not_found | :quota | String.t()}
  def apply_ops(id, raw_ops, by) do
    with {:ok, ops} <- State.normalize_ops(raw_ops),
         {:ok, _artifact} <- get(id) do
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        Enum.each(ops, &apply_op_in_db(id, &1, by, now))

        count = Repo.one(from e in StateEntry, where: e.artifact_id == ^id, select: count())

        if count > @max_state_rows do
          Repo.rollback(:quota)
        end

        ops
      end)
      |> case do
        {:ok, ops} ->
          if ops != [], do: broadcast(id, {:state_ops, ops, by})
          {:ok, ops}

        {:error, :quota} ->
          {:error, :quota}
      end
    end
  end

  defp apply_op_in_db(id, %{op: :delete, path: path}, _by, _now) do
    delete_subtree(id, path)
  end

  defp apply_op_in_db(id, %{op: :set, path: path, value: value}, by, now) do
    delete_subtree(id, path)

    case State.ancestors(path) do
      [] ->
        :ok

      ancestors ->
        Repo.delete_all(
          from e in StateEntry, where: e.artifact_id == ^id and e.path in ^ancestors
        )
    end

    rows =
      path
      |> State.flatten(value)
      |> Enum.map(fn {leaf, leaf_value} ->
        %{artifact_id: id, path: leaf, value: leaf_value, updated_by: by, updated_at: now}
      end)

    Repo.insert_all(StateEntry, rows,
      on_conflict: {:replace, [:value, :updated_by, :updated_at]},
      conflict_target: [:artifact_id, :path]
    )
  end

  defp delete_subtree(id, path) do
    prefix = path <> "."
    prefix_len = byte_size(prefix)

    Repo.delete_all(
      from e in StateEntry,
        where:
          e.artifact_id == ^id and
            (e.path == ^path or fragment("left(?, ?) = ?", e.path, ^prefix_len, ^prefix))
    )
  end

  ## Submissions

  @spec submit(String.t(), term(), String.t() | nil) ::
          {:ok, Submission.t()} | {:error, :not_found | :quota}
  def submit(id, payload, viewer_id) do
    with {:ok, artifact} <- get(id) do
      Repo.transaction(fn ->
        count = Repo.one(from s in Submission, where: s.artifact_id == ^id, select: count())

        if count >= @max_submissions do
          Repo.rollback(:quota)
        end

        Repo.insert!(%Submission{
          artifact_id: id,
          version: artifact.current_version,
          viewer_id: viewer_id,
          state: state(id),
          payload: payload,
          inserted_at: DateTime.utc_now()
        })
      end)
      |> case do
        {:ok, submission} ->
          broadcast(id, {:submission, submission})
          {:ok, submission}

        {:error, :quota} ->
          {:error, :quota}
      end
    end
  end

  @doc "Submissions with an id greater than `since`, oldest first."
  @spec submissions(String.t(), non_neg_integer()) :: [Submission.t()]
  def submissions(id, since \\ 0) do
    Repo.all(
      from s in Submission,
        where: s.artifact_id == ^id and s.id > ^since,
        order_by: [asc: s.id]
    )
  end

  @doc "The id of the newest submission, or 0."
  @spec last_submission_id(String.t()) :: non_neg_integer()
  def last_submission_id(id) do
    Repo.one(from s in Submission, where: s.artifact_id == ^id, select: max(s.id)) || 0
  end

  @doc """
  Blocks until a submission newer than `since` exists or `timeout_ms`
  passes. Subscribes before querying so a submission that lands between
  the two is not missed; a zero timeout is a single query.
  """
  @spec wait_for_submissions(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [Submission.t()]} | :timeout
  def wait_for_submissions(id, since, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    :ok = Phoenix.PubSub.subscribe(Artifacts.PubSub, topic(id))

    try do
      poll_submissions(id, since, deadline)
    after
      Phoenix.PubSub.unsubscribe(Artifacts.PubSub, topic(id))
    end
  end

  defp poll_submissions(id, since, deadline) do
    case submissions(id, since) do
      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          :timeout
        else
          receive do
            {:submission, _submission} -> poll_submissions(id, since, deadline)
            {:state_ops, _ops, _by} -> poll_submissions(id, since, deadline)
            {:version, _number, _by} -> poll_submissions(id, since, deadline)
          after
            remaining -> :timeout
          end
        end

      found ->
        {:ok, found}
    end
  end

  ## Helpers

  defp broadcast(id, message) do
    Phoenix.PubSub.broadcast(Artifacts.PubSub, topic(id), message)
  end

  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp validate_html(html) when is_binary(html) do
    cond do
      byte_size(html) > @max_html_bytes -> {:error, "html larger than 16 MiB"}
      not String.valid?(html) -> {:error, "html is not valid UTF-8"}
      true -> :ok
    end
  end

  defp validate_html(_other), do: {:error, "html must be a string"}

  defp validate_title(title) when is_binary(title) and title != "", do: :ok
  defp validate_title(_other), do: {:error, "title must be a non-empty string"}

  defp validate_optional_title(nil), do: :ok
  defp validate_optional_title(title), do: validate_title(title)
end
