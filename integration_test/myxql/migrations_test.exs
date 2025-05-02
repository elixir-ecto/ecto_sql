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

  text_variants = ~w/tinytext text mediumtext longtext/a
  @text_variants text_variants

  collation = "utf8mb4_bin"
  @collation collation

  defmodule CollateMigration do
    use Ecto.Migration

    @text_variants text_variants
    @collation collation

    def change do
      create table(:collate_reference) do
        add :name, :string, collation: @collation
      end

      create unique_index(:collate_reference, :name)

      create table(:collate) do
        add :string, :string, collation: @collation
        add :varchar, :varchar, size: 255, collation: @collation
        add :name_string, references(:collate_reference, type: :string, column: :name), collation: @collation

        for type <- @text_variants do
          add type, type, collation: @collation
        end
      end

      alter table(:collate) do
        modify :string, :string, collation: "utf8mb4_general_ci"
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

    test "collation can be set on a column" do
      num = @base_migration + System.unique_integer([:positive])
      assert :ok = Ecto.Migrator.up(PoolRepo, num, CollateMigration, log: false)
      query = fn column -> """
        SELECT collation_name
        FROM information_schema.columns
        WHERE table_name = 'collate' AND column_name = '#{column}';
      """
      end

      assert %{
        rows: [["utf8mb4_general_ci"]]
      } = Ecto.Adapters.SQL.query!(PoolRepo, query.("string"), [])

      for type <- ~w/text name_string/ ++ @text_variants do
        assert %{
          rows: [[@collation]]
        } = Ecto.Adapters.SQL.query!(PoolRepo, query.(type), [])
      end
    end
  end
end
