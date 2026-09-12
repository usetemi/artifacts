defmodule Artifacts.Artifact do
  @moduledoc "One published page: a stable id, a title, and a version counter."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "artifacts" do
    field :title, :string
    field :current_version, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          current_version: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
