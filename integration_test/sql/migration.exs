defmodule Ecto.Integration.MigrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.{TestRepo, PoolRepo}

  defmodule CreateMigration do
    use Ecto.Migration

    @table table(:create_table_migration)
    @index index(:create_table_migration, [:value], unique: true)

    def up do
      create @table do
        add :value, :integer
      end
      create @index
    end

    def down do
      drop @index
      drop @table
    end
  end

  defmodule AddColumnMigration do
    use Ecto.Migration

    def up do
      create table(:add_col_migration) do
        add :value, :integer
      end

      alter table(:add_col_migration) do
        add :to_be_added, :integer
      end

      execute "INSERT INTO add_col_migration (value, to_be_added) VALUES (1, 2)"
    end

    def down do
      drop table(:add_col_migration)
    end
  end

  defmodule AlterColumnMigration do
    use Ecto.Migration

    def up do
      create table(:alter_col_migration) do
        add :from_null_to_not_null, :integer
        add :from_not_null_to_null, :integer, null: false

        add :from_default_to_no_default, :integer, default: 0
        add :from_no_default_to_default, :integer
      end

      alter table(:alter_col_migration) do
        modify :from_null_to_not_null, :string, null: false
        modify :from_not_null_to_null, :string, null: true

        modify :from_default_to_no_default, :integer, default: nil
        modify :from_no_default_to_default, :integer, default: 0
      end

      execute "INSERT INTO alter_col_migration (from_null_to_not_null) VALUES ('foo')"
    end

    def down do
      drop table(:alter_col_migration)
    end
  end

  defmodule AlterColumnFromMigration do
    use Ecto.Migration

    def change do
      create table(:modify_from_authors, primary_key: false) do
        add :id, :integer, primary_key: true
      end
      create table(:modify_from_posts) do
        add :author_id, references(:modify_from_authors, type: :integer)
      end

      if direction() == :up do
        flush()
        PoolRepo.insert_all "modify_from_authors", [[id: 1]]
        PoolRepo.insert_all "modify_from_posts", [[author_id: 1]]
      end

      alter table(:modify_from_posts) do
        # remove the constraints modify_from_posts_author_id_fkey
        modify :author_id, :integer, from: references(:modify_from_authors, type: :integer)
      end
      alter table(:modify_from_authors) do
        modify :id, :bigint, from: :integer
      end
      alter table(:modify_from_posts) do
        # add the constraints modify_from_posts_author_id_fkey
        modify :author_id, references(:modify_from_authors, type: :bigint), from: :integer
      end
    end
  end

  defmodule AlterForeignKeyOnDeleteMigration do
    use Ecto.Migration

    def up do
      create table(:alter_fk_users)

      create table(:alter_fk_posts) do
        add :alter_fk_user_id, :id
      end

      alter table(:alter_fk_posts) do
        modify :alter_fk_user_id, references(:alter_fk_users, on_delete: :nilify_all)
      end

      execute "INSERT INTO alter_fk_users (id) VALUES ('1')"
      execute "INSERT INTO alter_fk_posts (id, alter_fk_user_id) VALUES ('1', '1')"
      execute "DELETE FROM alter_fk_users"
    end

    def down do
      drop table(:alter_fk_posts)
      drop table(:alter_fk_users)
    end
  end

  defmodule AlterForeignKeyOnUpdateMigration do
    use Ecto.Migration

    def up do
      create table(:alter_fk_users)

      create table(:alter_fk_posts) do
        add :alter_fk_user_id, :id
      end

      alter table(:alter_fk_posts) do
        modify :alter_fk_user_id, references(:alter_fk_users, on_update: :update_all)
      end

      execute "INSERT INTO alter_fk_users (id) VALUES ('1')"
      execute "INSERT INTO alter_fk_posts (id, alter_fk_user_id) VALUES ('1', '1')"
      execute "UPDATE alter_fk_users SET id = '2'"
    end

    def down do
      drop table(:alter_fk_posts)
      drop table(:alter_fk_users)
    end
  end

  defmodule DropColumnMigration do
    use Ecto.Migration

    def up do
      create table(:drop_col_migration) do
        add :value, :integer
        add :to_be_removed, :integer
      end

      execute "INSERT INTO drop_col_migration (value, to_be_removed) VALUES (1, 2)"

      alter table(:drop_col_migration) do
        remove :to_be_removed
      end
    end

    def down do
      drop table(:drop_col_migration)
    end
  end

  defmodule RenameColumnMigration do
    use Ecto.Migration

    def up do
      create table(:rename_col_migration) do
        add :to_be_renamed, :integer
      end

      rename table(:rename_col_migration), :to_be_renamed, to: :was_renamed

      execute "INSERT INTO rename_col_migration (was_renamed) VALUES (1)"
    end

    def down do
      drop table(:rename_col_migration)
    end
  end

  defmodule OnDeleteMigration do
    use Ecto.Migration

    def up do
      create table(:parent1)
      create table(:parent2)

      create table(:ref_migration) do
        add :parent1, references(:parent1, on_delete: :nilify_all)
      end

      alter table(:ref_migration) do
        add :parent2, references(:parent2, on_delete: :delete_all)
      end
    end

    def down do
      drop table(:ref_migration)
      drop table(:parent1)
      drop table(:parent2)
    end
  end

  defmodule ReferencesRollbackMigration do
    use Ecto.Migration

    def change do
      create table(:parent) do
        add :name, :string
      end

      create table(:child) do
        add :parent_id, references(:parent)
      end
    end
  end

  defmodule RenameMigration do
    use Ecto.Migration

    @table_current table(:posts_migration)
    @table_new table(:new_posts_migration)

    def up do
      create @table_current
      rename @table_current, to: @table_new
    end

    def down do
      drop @table_new
    end
  end

  defmodule PrefixMigration do
    use Ecto.Migration

    @prefix "ecto_prefix_test"

    def up do
      execute TestRepo.create_prefix(@prefix)
      create table(:first, prefix: @prefix)
      create table(:second, prefix: @prefix) do
        add :first_id, references(:first)
      end
    end

    def down do
      drop table(:second, prefix: @prefix)
      drop table(:first, prefix: @prefix)
      execute TestRepo.drop_prefix(@prefix)
    end
  end

  defmodule NoSQLMigration do
    use Ecto.Migration

    def up do
      create table(:collection, options: [capped: true])
      execute create: "collection"
    end
  end

  defmodule Parent do
    use Ecto.Schema

    schema "parent" do
    end
  end

  defmodule NoErrorTableMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:existing) do
        add :name, :string
      end

      create_if_not_exists table(:existing) do
        add :name, :string
      end

      create_if_not_exists table(:existing)

      drop_if_exists table(:existing)
      drop_if_exists table(:existing)
    end
  end

  defmodule NoErrorIndexMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists index(:posts, [:title])
      create_if_not_exists index(:posts, [:title])
      drop_if_exists index(:posts, [:title])
      drop_if_exists index(:posts, [:title])
    end
  end

  defmodule InferredDropIndexMigration do
    use Ecto.Migration

    def change do
      create index(:posts, [:title])
    end
  end

  defmodule AlterPrimaryKeyMigration do
    use Ecto.Migration

    def change do
      create table(:no_pk, primary_key: false) do
        add :dummy, :string
      end
      alter table(:no_pk) do
        add :id, :serial, primary_key: true
      end
    end
  end

  defmodule MigrationWithDynamicCommand do
    use Ecto.Migration

    alias Ecto.Adapters.SQL

    require Logger

    @disable_ddl_transaction true

    @migrate_first "select 'This is a first part of ecto.migrate';"
    @migrate_middle "select 'In the middle of ecto.migrate';"
    @migrate_second "select 'This is a second part of ecto.migrate';"
    @rollback_first "select 'This is a first part of ecto.rollback';"
    @rollback_middle "select 'In the middle of ecto.rollback';"
    @rollback_second "select 'This is a second part of ecto.rollback';"

    def change do
      execute @migrate_first, @rollback_second
      execute(fn -> Logger.info("This is a middle part called by execute") end)
      execute(&execute_up/0, &execute_down/0)
      execute @migrate_second, @rollback_first
    end

    defp execute_up, do: SQL.query!(repo(), @migrate_middle, [], [log: :info])
    defp execute_down, do: SQL.query!(repo(), @rollback_middle, [], [log: :info])
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  # Avoid migration out of order warnings
  @moduletag :capture_log
  @base_migration 1_000_000

  setup do
    {:ok, migration_number: System.unique_integer([:positive]) + @base_migration}
  end

  @tag :current
  test "migration with dynamic", %{migration_number: num} do
    level = :info
    args = [PoolRepo, num, MigrationWithDynamicCommand, [log: level]]

    for {name, direction} <- [migrate: :up, rollback: :down] do
      output = capture_log(fn -> :ok = apply(Ecto.Migrator, direction, args) end)
      lines = String.split(output, "\n")
      assert Enum.at(lines, 4) =~ "== Running #{num} #{inspect(MigrationWithDynamicCommand)}.change/0"
      assert Enum.at(lines, 6) =~ ~s[execute "select 'This is a first part of ecto.#{name}';"]
      {first_line, second_line} = if direction == :up, do: {8, 11}, else: {9, 11}
      assert Enum.at(lines, first_line) =~ get_middle_log(direction, first_line, name)
      assert Enum.at(lines, second_line) =~ get_middle_log(direction, second_line, name)
      assert Enum.at(lines, 13) =~ ~s[execute "select 'This is a second part of ecto.#{name}';"]
      assert Enum.at(lines, 15) =~ ~r"Migrated #{num} in \d.\ds"
    end
  end

  defp get_middle_log(:up, 8, _name), do: "This is a middle part called by execute"
  defp get_middle_log(:up, 11, name), do: "select 'In the middle of ecto.#{name}'; []"
  defp get_middle_log(:down, 9, name), do: get_middle_log(:up, 11, name)
  defp get_middle_log(:down, 11, name), do: get_middle_log(:up, 8, name)

  test "create and drop table and indexes", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, CreateMigration, log: false)
    assert :ok == down(PoolRepo, num, CreateMigration, log: false)
  end

  test "correctly infers how to drop index", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, InferredDropIndexMigration, log: false)
    assert :ok == down(PoolRepo, num, InferredDropIndexMigration, log: false)
  end

  test "supports references", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, OnDeleteMigration, log: false)

    parent1 = PoolRepo.insert! Ecto.put_meta(%Parent{}, source: "parent1")
    parent2 = PoolRepo.insert! Ecto.put_meta(%Parent{}, source: "parent2")

    writer = "INSERT INTO ref_migration (parent1, parent2) VALUES (#{parent1.id}, #{parent2.id})"
    PoolRepo.query!(writer)

    reader = from r in "ref_migration", select: {r.parent1, r.parent2}
    assert PoolRepo.all(reader) == [{parent1.id, parent2.id}]

    PoolRepo.delete!(parent1)
    assert PoolRepo.all(reader) == [{nil, parent2.id}]

    PoolRepo.delete!(parent2)
    assert PoolRepo.all(reader) == []

    assert :ok == down(PoolRepo, num, OnDeleteMigration, log: false)
  end

  test "rolls back references in change/1", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, ReferencesRollbackMigration, log: false)
    assert :ok == down(PoolRepo, num, ReferencesRollbackMigration, log: false)
  end

  test "create table if not exists and drop table if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorTableMigration, log: false)
  end

  @tag :create_index_if_not_exists
  test "create index if not exists and drop index if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorIndexMigration, log: false)
  end

  test "raises on NoSQL migrations", %{migration_number: num} do
    assert_raise ArgumentError, ~r"does not support keyword lists in :options", fn ->
      up(PoolRepo, num, NoSQLMigration, log: false)
    end
  end

  @tag :add_column
  test "add column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AddColumnMigration, log: false)
    assert [2] == PoolRepo.all from p in "add_col_migration", select: p.to_be_added
    :ok = down(PoolRepo, num, AddColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterColumnMigration, log: false)

    assert ["foo"] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_null_to_not_null
    assert [nil] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_not_null_to_null
    assert [nil] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_default_to_no_default
    assert [0] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_no_default_to_default

    query = "INSERT INTO alter_col_migration (from_not_null_to_null) VALUES ('foo')"
    assert catch_error(PoolRepo.query!(query))

    :ok = down(PoolRepo, num, AlterColumnMigration, log: false)
  end

  @tag :modify_column_with_from
  test "modify column with from", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterColumnFromMigration, log: false)

    assert [1] ==
           PoolRepo.all from p in "modify_from_posts", select: p.author_id

    :ok = down(PoolRepo, num, AlterColumnFromMigration, log: false)
  end

  @tag :modify_foreign_key_on_delete
  test "modify foreign key's on_delete constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterForeignKeyOnDeleteMigration, log: false)
    assert [nil] == PoolRepo.all from p in "alter_fk_posts", select: p.alter_fk_user_id
    :ok = down(PoolRepo, num, AlterForeignKeyOnDeleteMigration, log: false)
  end

  @tag :modify_foreign_key_on_update
  test "modify foreign key's on_update constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterForeignKeyOnUpdateMigration, log: false)
    assert [2] == PoolRepo.all from p in "alter_fk_posts", select: p.alter_fk_user_id
    :ok = down(PoolRepo, num, AlterForeignKeyOnUpdateMigration, log: false)
  end

  @tag :remove_column
  test "remove column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, DropColumnMigration, log: false)
    assert catch_error(PoolRepo.all from p in "drop_col_migration", select: p.to_be_removed)
    :ok = down(PoolRepo, num, DropColumnMigration, log: false)
  end

  @tag :rename_column
  test "rename column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, RenameColumnMigration, log: false)
    assert [1] == PoolRepo.all from p in "rename_col_migration", select: p.was_renamed
    :ok = down(PoolRepo, num, RenameColumnMigration, log: false)
  end

  @tag :rename_table
  test "rename table", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, RenameMigration, log: false)
    assert :ok == down(PoolRepo, num, RenameMigration, log: false)
  end

  @tag :prefix
  test "prefix", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, PrefixMigration, log: false)
    assert :ok == down(PoolRepo, num, PrefixMigration, log: false)
  end

  @tag :alter_primary_key
  test "alter primary key", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterPrimaryKeyMigration, log: false)
    assert :ok == down(PoolRepo, num, AlterPrimaryKeyMigration, log: false)
  end
end
