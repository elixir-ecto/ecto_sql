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

  collation = "Latin1_General_CS_AS"
  @collation collation

  defmodule CollateMigration do
    use Ecto.Migration
    @collation collation

    def change do
      create table(:collate_reference) do
        add :name, :string, collation: @collation
      end

      create unique_index(:collate_reference, :name)

      create table(:collate) do
        add :string, :string, collation: @collation
        add :char, :char, size: 255, collation: @collation
        add :nchar, :nchar, size: 255, collation: @collation
        add :varchar, :varchar, size: 255, collation: @collation
        add :nvarchar, :nvarchar, size: 255, collation: @collation
        add :text, :text,  collation: @collation
        add :ntext, :ntext, collation: @collation
        add :integer, :integer, collation: @collation
        add :name_string, references(:collate_reference, type: :string, column: :name), collation: @collation
      end

      alter table(:collate) do
        modify :string, :string,  collation: "Japanese_Bushu_Kakusu_100_CS_AS_KS_WS"
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

    test "collation can be set on a column" do
      num = @base_migration + System.unique_integer([:positive])
      assert :ok = Ecto.Migrator.up(PoolRepo, num, CollateMigration, log: :info)

      query = fn column -> """
        SELECT collation_name
        FROM information_schema.columns
        WHERE table_name = 'collate' AND column_name = '#{column}';
      """
      end

      assert %{
        rows: [["Japanese_Bushu_Kakusu_100_CS_AS_KS_WS"]]
      } = Ecto.Adapters.SQL.query!(PoolRepo, query.("string"), [])

      for type <- ~w/char varchar nchar nvarchar text ntext/ do
        assert %{
          rows: [[@collation]]
        } = Ecto.Adapters.SQL.query!(PoolRepo, query.(type), [])
      end

      assert %{
        rows: [[nil]]
      } = Ecto.Adapters.SQL.query!(PoolRepo, query.("integer"), [])
    end
  end
end
