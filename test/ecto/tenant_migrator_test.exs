defmodule Ecto.TenantMigratorTest do
  use ExUnit.Case

  import Ecto.Migrator
  import ExUnit.CaptureLog

  alias EctoSQL.TestRepo

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

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  def put_test_adapter_config(config) do
    Application.put_env(:ecto_sql, EctoSQL.TestAdapter, config)

    on_exit fn ->
      Application.delete_env(:ecto, EctoSQL.TestAdapter)
    end
  end

  describe "dynamic_repo option" do
    test "upwards and downwards migrations" do
      assert run(TestRepo, [{3, ChangeMigration}, {4, Migration}], :up, to: 4, log: false, dynamic_repo: :tenant_db) == [4]
      assert run(TestRepo, [{2, ChangeMigration}, {3, Migration}], :down, all: true, log: false, dynamic_repo: :tenant_db) == [3, 2]
    end

    test "down invokes the repository adapter with down commands" do
      assert down(TestRepo, 0, Migration, log: false, dynamic_repo: :tenant_db) == :already_down
      assert down(TestRepo, 2, Migration, log: false, dynamic_repo: :tenant_db) == :ok
    end

    test "up invokes the repository adapter with up commands" do
      assert up(TestRepo, 3, Migration, log: false, dynamic_repo: :tenant_db) == :already_up
      assert up(TestRepo, 4, Migration, log: false, dynamic_repo: :tenant_db) == :ok
    end

    test "migrations run inside a transaction if the adapter supports ddl transactions" do
      capture_log fn ->
        put_test_adapter_config(supports_ddl_transaction?: true, test_process: self())
        up(TestRepo, 0, Migration, dynamic_repo: :tenant_db)
        assert_receive {:transaction, _}
      end
    end
  end
end
