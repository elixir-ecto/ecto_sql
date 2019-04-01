defmodule Ecto.Migration.RunnerTest do
  use ExUnit.Case

  import Ecto.Migration.Runner

  alias EctoSQL.TestRepo

  describe "repo_name" do
    test "get by repo name" do
      {:ok, runner} = start_link(self(), TestRepo, :tenant_db, :forward, :up, %{level: false, sql: false})
      Process.put(:ecto_migration, %{runner: runner, prefix: nil})

      assert repo_name() == :tenant_db
      stop()
    end

    test "get by named repo" do
      {:ok, runner} = start_link(self(), TestRepo, TestRepo, :forward, :up, %{level: false, sql: false})
      Process.put(:ecto_migration, %{runner: runner, prefix: nil})

      assert repo_name() == TestRepo
      stop()
    end

    test "get when runner is not started" do
      assert_raise RuntimeError, ~r/could not find migration runner process/, fn ->
        repo_name()
      end
    end
  end
end
