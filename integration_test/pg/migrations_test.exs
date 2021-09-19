defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.PoolRepo
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

  test "logs Postgres notice messages" do
    log =
      capture_log(fn ->
        num = @base_migration + System.unique_integer([:positive])
        Ecto.Migrator.up(PoolRepo, num, DuplicateTableMigration, log: false)
      end)

    assert log =~ ~s(relation "duplicate_table" already exists, skipping)
  end

  describe "Migrator" do
    test ~s(logs LOCK command when log mode is set to "all") do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_sql_mode: "all")
        end)

      assert up_log =~ ~s(LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE)
      assert up_log =~ ~s(INSERT INTO "schema_migrations")
      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 2
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 2

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_sql_mode: "all")
        end)

      assert down_log =~ ~s(LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE)
      assert down_log =~ ~s(DELETE FROM "schema_migrations")
      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 2
      assert Regex.scan(~r/(commit \[\])/, down_log) |> length() == 2
    end

    test ~s(does not log LOCK command when log mode is set to "commands") do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_sql_mode: "commands")
        end)

      refute up_log =~ "begin"
      refute up_log =~ ~s(LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE)
      refute up_log =~ ~s(INSERT INTO "schema_migrations")
      refute up_log =~ "commit []"

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_sql_mode: "commands")
        end)

      refute down_log =~ "begin"
      refute down_log =~ ~s(LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE)
      refute down_log =~ ~s(DELETE FROM "schema_migrations")
      refute down_log =~ "commit []"
    end
  end
end
