defmodule Artifacts.Publishing.ChannelNotifier do
  @moduledoc """
  Broadcasts on `Phoenix.PubSub`, topic `"artifact:<id>"`, after each
  content action's transaction commits (DESIGN.md "Content changes" and
  plan §3). An `Ash.Notifier` fires only after commit — unlike an
  `after_transaction` hook, which would fire even if an outer transaction
  later rolls back — so a page, the chrome, and a `wait` caller never learn
  of a change that didn't happen.

  `notification.data` is always the `Artifact` record (the child row that
  triggered the notification is created inside the same `after_action`,
  never returned to the notifier); each content action attaches what this
  notifier needs onto that record's `__metadata__` before returning
  (`:ops` for `change_state`, `:submission_id` for `submit`).

  `create` is `publish` on a new Artifact (`Changes.PublishFirstVersion`
  calls the `publish` action internally), so `create` itself carries no
  clause here — the nested `publish` call's own notification covers
  version 1 too. Matching both would double-broadcast the same Version.
  """

  @behaviour Ash.Notifier

  alias Artifacts.Publishing.Actor

  @impl true
  def requires_original_data?(_resource, _action), do: false

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :publish}} = notification) do
    artifact = notification.data

    broadcast(
      artifact.id,
      {:version, %{version: artifact.current_version, by: ref(notification)}}
    )
  end

  def notify(%Ash.Notifier.Notification{action: %{name: :change_state}} = notification) do
    artifact = notification.data
    ops = Map.get(artifact.__metadata__, :ops)

    if ops && ops != [] do
      broadcast(artifact.id, {:state_ops, %{ops: ops, by: ref(notification)}})
    end
  end

  def notify(%Ash.Notifier.Notification{action: %{name: :submit}} = notification) do
    artifact = notification.data
    submission_id = Map.get(artifact.__metadata__, :submission_id)

    broadcast(artifact.id, {:submission, %{id: submission_id, by: ref(notification)}})
  end

  def notify(_notification), do: :ok

  defp broadcast(artifact_id, message) do
    Phoenix.PubSub.broadcast(Artifacts.PubSub, "artifact:#{artifact_id}", message)
  end

  defp ref(notification) do
    shared = (notification.changeset && notification.changeset.context[:shared]) || %{}
    Actor.ref(notification.actor, shared)
  end
end
