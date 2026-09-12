defmodule Artifacts.Artifact do
  @moduledoc """
  One published page: a stable id, a title, and a version counter.
  `archived_at` set means the page is hidden and closed to writes; the
  rows under it stay.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "artifacts" do
    field :title, :string
    field :current_version, :integer, default: 0
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          current_version: non_neg_integer(),
          archived_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
