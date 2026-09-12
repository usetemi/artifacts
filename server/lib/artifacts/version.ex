defmodule Artifacts.Version do
  @moduledoc "One immutable published HTML document of an artifact."

  use Ecto.Schema

  @primary_key false
  schema "versions" do
    field :artifact_id, :string, primary_key: true
    field :number, :integer, primary_key: true
    field :html, :string
    field :published_by, :string
    field :inserted_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          artifact_id: String.t(),
          number: pos_integer(),
          html: String.t(),
          published_by: String.t(),
          inserted_at: DateTime.t()
        }
end
