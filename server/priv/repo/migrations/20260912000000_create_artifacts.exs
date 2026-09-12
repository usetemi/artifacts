defmodule Artifacts.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :text, null: false
      add :current_version, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:versions, primary_key: false) do
      add :artifact_id, references(:artifacts, type: :string, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :number, :integer, null: false, primary_key: true
      add :html, :text, null: false
      add :published_by, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:state_entries, primary_key: false) do
      add :artifact_id, references(:artifacts, type: :string, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :path, :text, null: false, primary_key: true
      add :value, :jsonb, null: false
      add :updated_by, :text, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:submissions) do
      add :artifact_id, references(:artifacts, type: :string, on_delete: :delete_all), null: false

      add :version, :integer, null: false
      add :viewer_id, :text
      add :state, :jsonb, null: false
      add :payload, :jsonb
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:submissions, [:artifact_id, :id])
  end
end
