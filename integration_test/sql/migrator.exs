Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigratorTest do
  use Ecto.Integration.Case

  import Support.FileHelpers
  import ExUnit.CaptureLog
  import Ecto.Migrator

  alias Ecto.Integration.PoolRepo
  alias Ecto.Migration.SchemaMigration

  setup do
    PoolRepo.delete_all(SchemaMigration)
    :ok
  end

  defmodule AnotherSchemaMigration do
    use Ecto.Migration

    def change do
      execute PoolRepo.create_prefix("bad_schema_migrations"),
              PoolRepo.drop_prefix("bad_schema_migrations")

      create table(:schema_migrations, prefix: "bad_schema_migrations") do
        add :version, :string
        add :inserted_at, :integer
      end
    end
  end

  defmodule BrokenLinkMigration do
    use Ecto.Migration

    def change do
      Task.start_link(fn -> raise "oops" end)
      Process.sleep(:infinity)
    end
  end

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      create table(:good_migration)
    end

    def down do
      drop table(:good_migration)
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def change do
      execute "CREATE WHAT"
    end
  end

  test "migrations up and down" do
    assert migrated_versions(PoolRepo) == []
    assert up(PoolRepo, 31, GoodMigration, log: false) == :ok

    [migration] = PoolRepo.all(SchemaMigration)
    assert migration.version == 31
    assert migration.inserted_at

    assert migrated_versions(PoolRepo) == [31]
    assert up(PoolRepo, 31, GoodMigration, log: false) == :already_up
    assert migrated_versions(PoolRepo) == [31]
    assert down(PoolRepo, 32, GoodMigration, log: false) == :already_down
    assert migrated_versions(PoolRepo) == [31]
    assert down(PoolRepo, 31, GoodMigration, log: false) == :ok
    assert migrated_versions(PoolRepo) == []
  end

  test "does not commit migration if insert into schema migration fails" do
    # First we create a new schema migration table in another prefix
    assert up(PoolRepo, 33, AnotherSchemaMigration, log: false) == :ok
    assert migrated_versions(PoolRepo) == [33]

    assert capture_log(fn ->
      catch_error(up(PoolRepo, 34, GoodMigration, log: false, prefix: "bad_schema_migrations"))
      catch_error(PoolRepo.all("good_migration"))
      catch_error(PoolRepo.all("good_migration", prefix: "bad_schema_migrations"))
    end) =~ "Could not update schema migrations"

    assert down(PoolRepo, 33, AnotherSchemaMigration, log: false) == :ok
  end

  test "bad execute migration" do
    assert catch_error(up(PoolRepo, 31, BadMigration, log: false))
  end

  test "broken link migration" do
    Process.flag(:trap_exit, true)

    assert capture_log(fn ->
      {:ok, pid} = Task.start_link(fn -> up(PoolRepo, 31, BrokenLinkMigration, log: false) end)
      assert_receive {:EXIT, ^pid, _}
    end) =~ "oops"

    assert capture_log(fn ->
      catch_exit(up(PoolRepo, 31, BrokenLinkMigration, log: false))
    end) =~ "oops"
  end

  test "run up to/step migration" do
    in_tmp fn path ->
      create_migration(47)
      create_migration(48)

      assert [47] = run(PoolRepo, path, :up, step: 1, log: false)
      assert count_entries() == 1

      assert [48] = run(PoolRepo, path, :up, to: 48, log: false)
    end
  end

  test "run down to/step migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49),
        create_migration(50),
      ]

      assert [49, 50] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [50] = run(PoolRepo, path, :down, step: 1, log: false)
      purge migrations

      assert count_entries() == 1
      assert [50] = run(PoolRepo, path, :up, to: 50, log: false)
    end
  end

  test "runs all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53),
        create_migration(54),
      ]

      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
      assert [] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [54, 53] = run(PoolRepo, path, :down, all: true, log: false)
      purge migrations

      assert count_entries() == 0
      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
    end
  end

  test "raises when connection pool is too small" do
    config = Application.fetch_env!(:ecto_sql, PoolRepo)
    Application.put_env(:ecto_sql, __MODULE__.SingleConnectionRepo, Keyword.put(config, :pool_size, 1))

    defmodule SingleConnectionRepo do
      use Ecto.Repo, otp_app: :ecto_sql, adapter: PoolRepo.__adapter__
    end

    {:ok, _pid} = SingleConnectionRepo.start_link

    in_tmp fn path ->
      exception_message = ~r/Migrations failed to run because the connection pool size is less than 2/

      assert_raise Ecto.MigrationError, exception_message, fn ->
        run(SingleConnectionRepo, path, :up, all: true, log: false)
      end
    end
  end

  defp count_entries() do
    PoolRepo.aggregate(SchemaMigration, :count, :version)
  end

  defp create_migration(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        update &[#{num}|&1]
      end

      def down do
        update &List.delete(&1, #{num})
      end

      defp update(fun) do
        Process.put(:migrations, fun.(Process.get(:migrations) || []))
      end
    end
    """

    module
  end

  defp purge(modules) do
    Enum.each(List.wrap(modules), fn m ->
      :code.delete m
      :code.purge m
    end)
  end
end
