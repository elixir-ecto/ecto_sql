defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.AsyncFalsePoolRepo
  import ExUnit.CaptureLog

  @moduletag :capture_log
  @base_migration 3_000_000

  defmodule NormalMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:log_mode_table)
    end
  end

  defmodule AsyncFalseMigration do
    use Ecto.Migration
    @disable_async_migration true

    def change do
      create_if_not_exists table(:log_mode_table)
    end
  end

  describe "Migrator" do
    @get_lock_command ~s(sp_getapplock @Resource = 'ecto_Ecto.Integration.PoolRepo', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1)
    @get_lock_command_async_false ~s(sp_getapplock @Resource = 'ecto_Ecto.Integration.AsyncFalsePoolRepo', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1)
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

    test "async migration disabled through repo config" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(AsyncFalsePoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 1
      assert up_log =~ @get_lock_command_async_false
      assert up_log =~ @create_table_sql
      assert up_log =~ @create_table_log
      assert up_log =~ @version_insert
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 1

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(AsyncFalsePoolRepo, num, NormalMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 1
      assert down_log =~ @get_lock_command_async_false
      assert down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      assert down_log =~ @version_delete
      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 1
    end

    test "async migration disabled through migration module" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, AsyncFalseMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 1
      assert up_log =~ @get_lock_command
      assert up_log =~ @create_table_sql
      assert up_log =~ @create_table_log
      assert up_log =~ @version_insert
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 1

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, AsyncFalseMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 1
      assert down_log =~ @get_lock_command
      assert down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      assert down_log =~ @version_delete
      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 1
    end
  end
end
