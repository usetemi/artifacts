defmodule Artifacts.Submission do
  @moduledoc """
  A snapshot taken when a viewer (or the agent) presses Submit: the state
  at that moment, an optional payload, who submitted, and which version
  was showing. The integer id is the cursor `wait` resumes from.
  """

  use Ecto.Schema

  schema "submissions" do
    field :artifact_id, :string
    field :version, :integer
    field :viewer_id, :string
    field :state, :map
    field :payload, Artifacts.JSON
    field :inserted_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          id: pos_integer(),
          artifact_id: String.t(),
          version: non_neg_integer(),
          viewer_id: String.t() | nil,
          state: map(),
          payload: term(),
          inserted_at: DateTime.t()
        }
end
