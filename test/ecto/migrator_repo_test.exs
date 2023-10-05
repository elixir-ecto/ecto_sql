defmodule Ecto.MigratorRepoTest do
  use ExUnit.Case

  import Ecto.Migrator
  import ExUnit.CaptureLog

  defmodule Migration do
    use Ecto.Migration

    def up do
      execute "up"
    end

    def down do
      execute "down"
    end
  end

  defmodule ChangeMigration do
    use Ecto.Migration

    def change do
      create table(:posts) do
        add :name, :string
      end

      create index(:posts, [:title])
    end
  end

  defmodule MainRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter
  end

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter
  end

  Application.put_env(:ecto_sql, MainRepo, migration_repo: MigrationRepo)

  setup do
    {:ok, _} = start_supervised({MigrationsAgent, [{1, nil}, {2, nil}, {3, nil}]})
    :ok
  end

  def put_test_adapter_config(config) do
    Application.put_env(:ecto_sql, EctoSQL.TestAdapter, config)

    on_exit(fn ->
      Application.delete_env(:ecto, EctoSQL.TestAdapter)
    end)
  end

  setup_all do
    {:ok, _pid} = MainRepo.start_link()
    {:ok, _pid} = MigrationRepo.start_link()
    :ok
  end

  describe "migration_repo option" do
    test "upwards and downwards migrations" do
      assert run(MainRepo, [{3, ChangeMigration}, {4, Migration}], :up, to: 4, log: false) == [4]

      assert run(MainRepo, [{2, ChangeMigration}, {3, Migration}], :down, all: true, log: false) ==
               [3, 2]
    end

    test "down invokes the repository adapter with down commands" do
      assert down(MainRepo, 0, Migration, log: false) == :already_down
      assert down(MainRepo, 2, Migration, log: false) == :ok
    end

    test "up invokes the repository adapter with up commands" do
      assert up(MainRepo, 3, Migration, log: false) == :already_up
      assert up(MainRepo, 4, Migration, log: false) == :ok
    end

    test "migrations run inside a transaction if the adapter supports ddl transactions when configuring a migration repo" do
      capture_log(fn ->
        put_test_adapter_config(supports_ddl_transaction?: true, test_process: self())
        up(MainRepo, 0, Migration)

        assert_receive {:transaction, %{repo: MainRepo}, _}
        assert_receive {:lock_for_migrations, %{repo: MigrationRepo}, _, _}
      end)
    end
  end
end
