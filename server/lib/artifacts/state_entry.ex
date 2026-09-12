defmodule Artifacts.StateEntry do
  @moduledoc "One leaf of an artifact's shared state: a dotted path and a JSON value."

  use Ecto.Schema

  @primary_key false
  schema "state_entries" do
    field :artifact_id, :string, primary_key: true
    field :path, :string, primary_key: true
    field :value, Artifacts.JSON
    field :updated_by, :string
    field :updated_at, :utc_datetime_usec
  end
end
