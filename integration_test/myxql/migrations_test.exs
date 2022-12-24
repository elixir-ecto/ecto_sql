Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo
  import ExUnit.CaptureLog
  import Support.FileHelpers
  import Ecto.Migrator

  @moduletag :capture_log
  @base_migration 3_000_000

  defmodule NormalMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:log_mode_table)
    end
  end

  defmodule ExecuteFileReversibleMigration do
    use Ecto.Migration

    def change do
      execute_file "up.sql", "down.sql"
    end
  end

  defmodule ExecuteFileNonReversibleMigration do
    use Ecto.Migration

    def up do
      execute_file "up.sql"
    end

    def down do
      execute_file "down.sql"
    end
  end

  test "execute_file" do
    in_tmp fn _path ->
      migration_version = System.unique_integer([:positive])
      table = "execute_file_table"
      File.write!("up.sql", ~s(CREATE TABLE IF NOT EXISTS #{table} \(i integer\)))
      File.write!("down.sql", ~s(DROP TABLE IF EXISTS #{table}))

      # non-reversible
      up(PoolRepo, version, ExecuteFileNonReversibleMigration, log: false)
      PoolRepo.query!("SELECT * FROM #{table}")
      down(PoolRepo, version, ExecuteFileNonReversibleMigration, log: false)

      assert_raise MyXQL.Error, ~r/'ecto_test.#{table}' doesn't exist/, fn ->
        PoolRepo.query!("SELECT * FROM #{table}")
      end

      # reversible
      up(PoolRepo, version, ExecuteFileReversibleMigration, log: false)
      PoolRepo.query!("SELECT * FROM #{table}")
      down(PoolRepo, version, ExecuteFileReversibleMigration, log: false)

      assert_raise MyXQL.Error, ~r/'ecto_test.#{table}' doesn't exist/, fn ->
        PoolRepo.query!("SELECT * FROM #{table}")
      end
    end
  end

  describe "Migrator" do
    @get_lock_command ~s[SELECT GET_LOCK('ecto_Ecto.Integration.PoolRepo', -1)]
    @release_lock_command ~s[SELECT RELEASE_LOCK('ecto_Ecto.Integration.PoolRepo')]
    @create_table_sql ~s[CREATE TABLE IF NOT EXISTS `log_mode_table`]
    @create_table_log "create table if not exists log_mode_table"
    @drop_table_sql ~s[DROP TABLE IF EXISTS `log_mode_table`]
    @drop_table_log "drop table if exists log_mode_table"
    @version_insert ~s[INSERT INTO `schema_migrations`]
    @version_delete ~s[DELETE s0.* FROM `schema_migrations`]

    test "logs locking and transaction commands" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert up_log =~ "begin []"
      assert up_log =~ @get_lock_command
      assert up_log =~ @create_table_sql
      assert up_log =~ @create_table_log
      assert up_log =~ @release_lock_command
      assert up_log =~ @version_insert
      assert up_log =~ "commit []"

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert down_log =~ "begin []"
      assert down_log =~ @get_lock_command
      assert down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      assert down_log =~ @release_lock_command
      assert down_log =~ @version_delete
      assert down_log =~ "commit []"
    end

    test "does not log sql when log is default" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log: :info)
        end)

      refute up_log =~ "begin []"
      refute up_log =~ @get_lock_command
      refute up_log =~ @create_table_sql
      assert up_log =~ @create_table_log
      refute up_log =~ @release_lock_command
      refute up_log =~ @version_insert
      refute up_log =~ "commit []"

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log: :info)
        end)

      refute down_log =~ "begin []"
      refute down_log =~ @get_lock_command
      refute down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      refute down_log =~ @release_lock_command
      refute down_log =~ @version_delete
      refute down_log =~ "commit []"
    end
  end
end
