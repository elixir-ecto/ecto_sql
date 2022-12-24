defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.AdvisoryLockPoolRepo
  import ExUnit.CaptureLog

  @moduletag :capture_log
  @base_migration 3_000_000

  defmodule DuplicateTableMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:duplicate_table)
      create_if_not_exists table(:duplicate_table)
    end
  end

  defmodule NormalMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:log_mode_table)
    end
  end

  defmodule IndexMigration do
    use Ecto.Migration
    @disable_ddl_transaction true

    def change do
      create_if_not_exists table(:index_table) do
        add :name, :string
        add :custom_id, :uuid
        timestamps()
      end

      create_if_not_exists index(:index_table, [:name], concurrently: true)
    end
  end

  test "logs Postgres notice messages" do
    log =
      capture_log(fn ->
        num = @base_migration + System.unique_integer([:positive])
        Ecto.Migrator.up(PoolRepo, num, DuplicateTableMigration, log: false)
      end)

    assert log =~ ~s(relation "duplicate_table" already exists, skipping)
  end

  describe "Migrator" do
    @get_lock_command ~s(LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE)
    @get_advisory_lock_command ~s[SELECT pg_try_advisory_lock(129653361)]
    @release_advisory_lock_command ~s[SELECT pg_advisory_unlock(129653361)]
    @create_table_sql ~s(CREATE TABLE IF NOT EXISTS "log_mode_table")
    @create_table_log "create table if not exists log_mode_table"
    @drop_table_sql ~s(DROP TABLE IF EXISTS "log_mode_table")
    @drop_table_log "drop table if exists log_mode_table"
    @version_insert ~s(INSERT INTO "schema_migrations")
    @advisory_version_insert ~s(INSERT INTO "advisory_lock_schema_migrations")
    @version_delete ~s(DELETE FROM "schema_migrations")
    @advisory_version_delete ~s(DELETE FROM "advisory_lock_schema_migrations")

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

      assert down_log =~ "begin []"
      assert down_log =~ @get_lock_command
      assert down_log =~ @drop_table_sql
      assert down_log =~ @drop_table_log
      assert down_log =~ @version_delete
      assert down_log =~ "commit []"
    end

    test "logs advisory lock and transaction commands" do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(AdvisoryLockPoolRepo, num, IndexMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      refute up_log =~ @get_lock_command
      refute up_log =~ "begin []"
      assert up_log =~ @get_advisory_lock_command
      refute up_log =~ @version_insert
      assert up_log =~ @advisory_version_insert
      refute up_log =~ "commit []"
      assert up_log =~ @release_advisory_lock_command

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(AdvisoryLockPoolRepo, num, IndexMigration, log_migrator_sql: :info, log_migrations_sql: :info, log: :info)
        end)

      refute down_log =~ "begin []"
      refute down_log =~ @get_lock_command
      assert down_log =~ @get_advisory_lock_command
      refute down_log =~ @version_delete
      assert down_log =~ @advisory_version_delete
      refute down_log =~ "commit []"
      assert down_log =~ @release_advisory_lock_command
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
