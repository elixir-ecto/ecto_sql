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
      File.write!("up.sql", ~s(CREATE TABLE #{table} \(i integer\)))
      File.write!("down.sql", ~s(DROP TABLE #{table}))

      # non-reversible
      up(PoolRepo, migration_version, ExecuteFileNonReversibleMigration, log: false)
      PoolRepo.query!("SELECT * FROM #{table}")
      down(PoolRepo, migration_version, ExecuteFileNonReversibleMigration, log: false)

      assert_raise Tds.Error, ~r/Invalid object name '#{table}'/, fn ->
        PoolRepo.query!("SELECT * FROM #{table}")
      end

      # reversible
      up(PoolRepo, migration_version, ExecuteFileReversibleMigration, log: false)
      PoolRepo.query!("SELECT * FROM #{table}")
      down(PoolRepo, migration_version, ExecuteFileReversibleMigration, log: false)

      assert_raise Tds.Error, ~r/Invalid object name '#{table}'/, fn ->
        PoolRepo.query!("SELECT * FROM #{table}")
      end
    end
  end

  describe "Migrator" do
    @get_lock_command ~s(sp_getapplock @Resource = 'ecto_Ecto.Integration.PoolRepo', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1)
    @create_table_sql ~s(CREATE TABLE [log_mode_table])
    @create_table_log "create table if not exists log_mode_table"
    @drop_table_sql ~s(DROP TABLE [log_mode_table])
    @drop_table_log "drop table if exists log_mode_table"
    @version_insert ~s(INSERT INTO [schema_migrations])
    @version_delete ~s(DELETE s0 FROM [schema_migrations])

    test "logs locking and transaction commands" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 2
      assert up_log =~ @get_lock_command
      assert up_log =~ @create_table_sql
      assert up_log =~ @create_table_log
      assert up_log =~ @version_insert
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 2

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 2
      assert down_log =~ @get_lock_command
      assert down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      assert down_log =~ @version_delete
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 2
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
      refute down_log =~ @version_delete
      refute down_log =~ "commit []"
    end
  end
end
