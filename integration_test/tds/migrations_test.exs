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

  describe "Migrator" do
    test ~s(logs GET_LOCK RELEASE_LOCK and transaction commands when log mode is set to "all") do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_sql_mode: "all")
        end)

      assert up_log =~ ~s(sp_getapplock @Resource = 'ecto_Ecto.Integration.PoolRepo', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1)
      assert up_log =~ ~s(INSERT INTO [schema_migrations])
      assert Regex.scan(~r/(begin \[\])/, up_log) |> length() == 2
      assert Regex.scan(~r/(commit \[\])/, up_log) |> length() == 2

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_sql_mode: "all")
        end)

      assert down_log =~ ~s(sp_getapplock @Resource = 'ecto_Ecto.Integration.PoolRepo', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1)
      assert down_log =~ ~s(DELETE s0 FROM [schema_migrations])
      assert Regex.scan(~r/(begin \[\])/, down_log) |> length() == 2
      assert Regex.scan(~r/(commit \[\])/, down_log) |> length() == 2
    end

    test ~s(does not log GET_LOCK RELEASE_LOCK and transaction commands when log mode is set to "commands") do
      num = @base_migration + System.unique_integer([:positive])
      up_log =
        capture_log(fn ->
          Ecto.Migrator.up(PoolRepo, num, NormalMigration, log_sql_mode: "commands")
        end)

      refute up_log =~ "begin"
      refute up_log =~ ~s[sp_getapplock]
      refute up_log =~ ~s[SELECT GET_LOCK(ecto_PoolRepo)]
      refute up_log =~ ~s[SELECT RELEASE_LOCK(ecto_PoolRepo)]
      refute up_log =~ "commit []"

      down_log =
        capture_log(fn ->
          Ecto.Migrator.down(PoolRepo, num, NormalMigration, log_sql_mode: "commands")
        end)

      refute down_log =~ "begin"
      refute down_log =~ ~s[sp_getapplock]
      refute down_log =~ ~s[SELECT RELEASE_LOCK(ecto_PoolRepo)]
      refute down_log =~ ~s[DELETE FROM "schema_migrations"]
      refute down_log =~ "commit []"
    end
  end
end
