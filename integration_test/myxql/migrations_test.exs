defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo
  import ExUnit.CaptureLog

  @moduletag :capture_log
  @base_migration 3_000_000

  defmodule NormalMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:log_mode_table)
    end
  end

  defmodule AlterMigration do
    use Ecto.Migration

    def change do
      create table(:alter_table) do
        add(:column1, :string)
      end

      alter table(:alter_table) do
        add(:column2, :string, after: :column1, comment: "second column")
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

    test "add column with after and comment options" do
      num = @base_migration + System.unique_integer([:positive])

      log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, AlterMigration, log_migrations_sql: :info)
        end)

      assert log =~ "ALTER TABLE `alter_table` ADD `column2` varchar(255) COMMENT 'second column' AFTER `column1`"
    end
  end
end
