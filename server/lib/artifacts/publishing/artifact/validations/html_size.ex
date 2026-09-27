defmodule Artifacts.Publishing.Artifact.Validations.HtmlSize do
  @moduledoc """
  Validates the `html` argument on `publish`: a string, valid UTF-8, at
  most 16 MiB (DESIGN.md "Content changes", "Caps"). `create` delegates
  its own `html` argument straight to `publish` (`Changes.
  PublishFirstVersion`), so this one validation covers both.
  """

  use Ash.Resource.Validation

  @max_bytes 16 * 1024 * 1024

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :html) do
      html when not is_binary(html) ->
        {:error, field: :html, message: "must be a string"}

      html ->
        cond do
          not String.valid?(html) ->
            {:error, field: :html, message: "is not valid UTF-8"}

          byte_size(html) > @max_bytes ->
            {:error, field: :html, message: "must be 16 MiB or smaller"}

          true ->
            :ok
        end
    end
  end
end
