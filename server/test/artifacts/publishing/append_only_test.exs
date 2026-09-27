defmodule Artifacts.Publishing.AppendOnlyTest do
  use Artifacts.DataCase, async: false

  import Artifacts.AccountsFixtures
  import Artifacts.PublishingFixtures

  alias Artifacts.Repo

  describe "the BEFORE UPDATE OR DELETE trigger" do
    test "refuses an UPDATE and a DELETE on versions, submissions, and events" do
      user = user_fixture!()
      artifact = artifact_fixture!(user)
      {:ok, submitted} = Artifacts.Publishing.submit(artifact, nil, actor: user)
      submission_id = submitted.__metadata__.submission_id

      assert_refuses("versions", "number = 1 AND artifact_id = '#{artifact.id}'", "html = 'x'")
      assert_refuses("submissions", "id = #{submission_id}", "version = 99")

      [[event_id]] =
        Repo.query!("SELECT id FROM events WHERE artifact_id = $1 LIMIT 1", [artifact.id]).rows

      assert_refuses("events", "id = #{event_id}", "kind = 'state_changed'")
    end

    defp assert_refuses(table, where, set) do
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(fn ->
          Repo.query!("UPDATE #{table} SET #{set} WHERE #{where}")
        end)
      end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(fn ->
          Repo.query!("DELETE FROM #{table} WHERE #{where}")
        end)
      end
    end
  end
end
