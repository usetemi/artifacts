defmodule Artifacts.Repo.Migrations.AddEventsAndArchive do
  use Ecto.Migration

  def change do
    alter table(:artifacts) do
      add :archived_at, :utc_datetime_usec
    end

    # The record of everything that happened to an artifact. It restricts
    # deletion of its artifact so that no path, not even a manual one,
    # can drop a history.
    create table(:events) do
      add :artifact_id, references(:artifacts, type: :string, on_delete: :restrict), null: false
      add :kind, :text, null: false
      add :actor, :text, null: false
      add :data, :jsonb, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:events, [:artifact_id, :id])
  end
end
