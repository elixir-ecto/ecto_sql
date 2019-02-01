defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo

  # Avoid migration out of order warnings
  @moduletag :capture_log
  @base_migration 3_000_000

  setup do
    {:ok, migration_number: System.unique_integer([:positive]) + @base_migration}
  end

  defmodule AddColumnIfNotExistsMigration do
    use Ecto.Migration

    def up do
      create table(:add_col_if_not_exists_migration)

      alter table(:add_col_if_not_exists_migration) do
        add_if_not_exists :value, :integer
        add_if_not_exists :to_be_added, :integer
      end

      execute "INSERT INTO add_col_if_not_exists_migration (value, to_be_added) VALUES (1, 2)"
    end

    def down do
      drop table(:add_col_if_not_exists_migration)
    end
  end

  defmodule DropColumnIfExistsMigration do
    use Ecto.Migration

    def up do
      create table(:drop_col_if_exists_migration) do
        add :value, :integer
        add :to_be_removed, :integer
      end

      execute "INSERT INTO drop_col_if_exists_migration (value, to_be_removed) VALUES (1, 2)"

      alter table(:drop_col_if_exists_migration) do
        remove_if_exists :to_be_removed, :integer
      end
    end

    def down do
      drop table(:drop_col_if_exists_migration)
    end
  end

  defmodule DuplicateTableMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:duplicate_table)
      create_if_not_exists table(:duplicate_table)
    end
  end

  defmodule NoErrorOnConditionalColumnMigration do
    use Ecto.Migration

    def up do
      create table(:no_error_on_conditional_column_migration)

      alter table(:no_error_on_conditional_column_migration) do
        add_if_not_exists  :value, :integer
        add_if_not_exists  :value, :integer

        remove_if_exists :value, :integer
        remove_if_exists :value, :integer
      end
    end

    def down do
      drop table(:no_error_on_conditional_column_migration)
    end
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]

  test "logs Postgres notice messages" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        num = @base_migration + System.unique_integer([:positive])
        up(PoolRepo, num, DuplicateTableMigration, log: false)
      end)

    assert log =~ ~s(relation "duplicate_table" already exists, skipping)
  end

  @tag :no_error_on_conditional_column_migration
  test "add if not exists and drop if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorOnConditionalColumnMigration, log: false)
    assert :ok == down(PoolRepo, num, NoErrorOnConditionalColumnMigration, log: false)
  end

  @tag :add_column_if_not_exists
  test "add column if not exists", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AddColumnIfNotExistsMigration, log: false)
    assert [2] == PoolRepo.all from p in "add_col_if_not_exists_migration", select: p.to_be_added
    :ok = down(PoolRepo, num, AddColumnIfNotExistsMigration, log: false)
  end

  @tag :remove_column_if_exists
  test "remove column when exists", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, DropColumnIfExistsMigration, log: false)
    assert catch_error(PoolRepo.all from p in "drop_col_if_exists_migration", select: p.to_be_removed)
    :ok = down(PoolRepo, num, DropColumnIfExistsMigration, log: false)
  end
end
