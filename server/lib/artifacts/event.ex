defmodule Artifacts.Event do
  @moduledoc """
  One entry in an artifact's append-only record: what happened, who did
  it, and when. The other tables hold the current view; events hold the
  history that state rows overwrite, so how a page went from the agent's
  draft to what was finally submitted can always be read back.

  `kind` is one of `version`, `state_op`, `submission`, `archive`. `data`
  points at the row a version or submission event describes and holds a
  state op inline.
  """

  use Ecto.Schema

  schema "events" do
    field :artifact_id, :string
    field :kind, :string
    field :actor, :string
    field :data, :map
    field :inserted_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          id: pos_integer(),
          artifact_id: String.t(),
          kind: String.t(),
          actor: String.t(),
          data: map(),
          inserted_at: DateTime.t()
        }
end
