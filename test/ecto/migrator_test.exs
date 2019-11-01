defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Ecto.Migrator
  import ExUnit.CaptureLog

  alias EctoSQL.TestRepo
  alias Ecto.Migration.SchemaMigration

  defmodule Migration do
    use Ecto.Migration

    def up do
      execute "up"
    end

    def down do
      execute "down"
    end
  end

  defmodule ChangeMigration do
    use Ecto.Migration

    def change do
      create table(:posts) do
        add :name, :string
      end

      create index(:posts, [:title])
    end
  end

  defmodule ChangeMigrationPrefix do
    use Ecto.Migration

    def change do
      create table(:comments, prefix: :foo) do
        add :name, :string
      end

      create index(:posts, [:title], prefix: :foo)
    end
  end

  defmodule UpDownMigration do
    use Ecto.Migration

    def up do
      alter table(:posts) do
        add :name, :string
      end
    end

    def down do
      execute "foo"
    end
  end

  defmodule NoTransactionMigration do
    use Ecto.Migration
    @disable_ddl_transaction true

    def change do
      create index(:posts, [:foo])
    end
  end

  defmodule NoLockMigration do
    use Ecto.Migration
    @disable_migration_lock true

    def change do
      create index(:posts, [:foo])
    end
  end

  defmodule MigrationWithCallbacks do
    use Ecto.Migration

    def after_begin() do
      execute "after_begin", "after_begin_down"
    end

    def before_commit() do
      execute "before_commit", "before_commit_down"
    end

    def change do
      create index(:posts, [:foo])
    end
  end

  defmodule MigrationWithCallbacksAndNoTransaction do
    use Ecto.Migration

    @disable_ddl_transaction true

    def after_begin() do
      execute "after_begin", "after_begin_down"
    end

    def before_commit() do
      execute "before_commit", "before_commit_down"
    end

    def change do
      create index(:posts, [:foo])
    end
  end

  defmodule ExecuteOneAnonymousFunctionMigration do
    use Ecto.Migration

    require Logger

    def change do
      execute(fn -> Logger.info("This should fail on rollback.") end)
    end
  end

  defmodule ExecuteTwoAnonymousFunctionsMigration do
    use Ecto.Migration

    require Logger

    @disable_ddl_transaction true

    @migrate_first "select 'This is a first part of ecto.migrate';"
    @migrate_middle "select 'In the middle of ecto.migrate';"
    @migrate_second "select 'This is a second part of ecto.migrate';"
    @rollback_first "select 'This is a first part of ecto.rollback';"
    @rollback_middle "select 'In the middle of ecto.rollback';"
    @rollback_second "select 'This is a second part of ecto.rollback';"

    def change do
      execute(@migrate_first, @rollback_second)
      execute(&execute_up/0, &execute_down/0)
      execute(@migrate_second, @rollback_first)
    end

    defp execute_up, do: Logger.info(@migrate_middle)
    defp execute_down, do: Logger.info(@rollback_middle)
  end

  defmodule InvalidMigration do
    use Ecto.Migration
  end

  defmodule EmptyModule do
  end

  defmodule MigrationSourceRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter
  end

  defmodule EmptyUpDownMigration do
    use Ecto.Migration

    def up, do: flush()
    def down, do: flush()
  end

  defmodule EmptyChangeMigration do
    use Ecto.Migration

    def change, do: flush()
  end

  Application.put_env(:ecto_sql, MigrationSourceRepo, [migration_source: "my_schema_migrations"])

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  def put_test_adapter_config(config) do
    Application.put_env(:ecto_sql, EctoSQL.TestAdapter, config)

    on_exit fn ->
      Application.delete_env(:ecto, EctoSQL.TestAdapter)
    end
  end

  defp create_migration(name, opts \\ []) do
    module = name |> Path.basename |> Path.rootname

    File.write! name, """
    defmodule Ecto.MigrationTest.S#{module} do
      use Ecto.Migration

      #{Enum.map_join(opts, "\n", &"@#{&1} true")}

      def up do
        execute "up"
      end

      def down do
        execute "down"
      end
    end
    """
  end

  test "execute one anonymous function" do
    module = ExecuteOneAnonymousFunctionMigration
    num = System.unique_integer([:positive])
    capture_log(fn -> :ok = up(TestRepo, num, module, [log: false]) end)
    message = "no function clause matching in Ecto.Migration.Runner.command/1"
    assert_raise(FunctionClauseError, message, fn -> down(TestRepo, num, module, [log: false]) end)
  end

  test "execute two anonymous functions" do
    module = ExecuteTwoAnonymousFunctionsMigration
    num = System.unique_integer([:positive])
    args = [TestRepo, num, module, [log: :info]]

    for {name, direction} <- [migrate: :up, rollback: :down] do
      output = capture_log(fn -> :ok = apply(Ecto.Migrator, direction, args) end)
      lines = String.split(output, "\n")
      assert Enum.at(lines, 1) =~ "== Running #{num} #{inspect(module)}.change/0"
      assert Enum.at(lines, 3) =~ ~s[execute "select 'This is a first part of ecto.#{name}';"]
      assert Enum.at(lines, 5) =~ "select 'In the middle of ecto.#{name}';"
      assert Enum.at(lines, 7) =~ ~s[execute "select 'This is a second part of ecto.#{name}';"]
      assert Enum.at(lines, 9) =~ ~r"Migrated #{num} in \d.\ds"
    end
  end

  test "flush" do
    num = System.unique_integer([:positive])
    assert :ok == up(TestRepo, num, EmptyUpDownMigration, log: false)
    assert :ok == down(TestRepo, num, EmptyUpDownMigration, log: false)
    assert :ok == up(TestRepo, num, EmptyChangeMigration, log: false)
    message = "calling flush() inside change when doing rollback is not supported."
    assert_raise(RuntimeError, message, fn ->
      down(TestRepo, num, EmptyChangeMigration, log: false)
    end)
  end

  test "custom schema migrations table is right" do
    assert SchemaMigration.get_source(TestRepo) == "schema_migrations"
    assert SchemaMigration.get_source(MigrationSourceRepo) == "my_schema_migrations"
  end

  test "logs migrations" do
    output = capture_log fn ->
      :ok = up(TestRepo, 10, ChangeMigration)
    end

    assert output =~ "== Running 10 Ecto.MigratorTest.ChangeMigration.change/0 forward"
    assert output =~ "create table posts"
    assert output =~ "create index posts_title_index"
    assert output =~ ~r"== Migrated 10 in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 10, ChangeMigration)
    end

    assert output =~ "== Running 10 Ecto.MigratorTest.ChangeMigration.change/0 backward"
    assert output =~ "drop table posts"
    assert output =~ "drop index posts_title_index"
    assert output =~ ~r"== Migrated 10 in \d.\ds"

    output = capture_log fn ->
      :ok = up(TestRepo, 11, ChangeMigrationPrefix)
    end

    assert output =~ "== Running 11 Ecto.MigratorTest.ChangeMigrationPrefix.change/0 forward"
    assert output =~ "create table foo.comments"
    assert output =~ "create index foo.posts_title_index"
    assert output =~ ~r"== Migrated 11 in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 11, ChangeMigrationPrefix)
    end

    assert output =~ "== Running 11 Ecto.MigratorTest.ChangeMigrationPrefix.change/0 backward"
    assert output =~ "drop table foo.comments"
    assert output =~ "drop index foo.posts_title_index"
    assert output =~ ~r"== Migrated 11 in \d.\ds"

    output = capture_log fn ->
      :ok = up(TestRepo, 12, UpDownMigration)
    end

    assert output =~ "== Running 12 Ecto.MigratorTest.UpDownMigration.up/0 forward"
    assert output =~ "alter table posts"
    assert output =~ ~r"== Migrated 12 in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 12, UpDownMigration)
    end

    assert output =~ "== Running 12 Ecto.MigratorTest.UpDownMigration.down/0 forward"
    assert output =~ "execute \"foo\""
    assert output =~ ~r"== Migrated 12 in \d.\ds"
  end

  test "up raises error in strict mode" do
    assert_raise Ecto.MigrationError, fn ->
      up(TestRepo, 0, Migration, log: false, strict_version_order: true)
    end
  end

  test "up invokes the repository adapter with up commands" do
    assert capture_log(fn ->
      assert up(TestRepo, 0, Migration, log: false) == :ok
    end) =~ "You are running migration 0 but an older migration with version 3 has already run"

    assert up(TestRepo, 1, Migration, log: false) == :already_up
    assert up(TestRepo, 10, ChangeMigration, log: false) == :ok
  end

  test "down invokes the repository adapter with down commands" do
    assert down(TestRepo, 0, Migration, log: false) == :already_down
    assert down(TestRepo, 1, Migration, log: false) == :ok
    assert down(TestRepo, 2, ChangeMigration, log: false) == :ok
  end

  test "up raises error when missing up/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.up(TestRepo, 10, InvalidMigration, log: false)
    end
  end

  test "down raises error when missing down/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.down(TestRepo, 1, InvalidMigration, log: false)
    end
  end

  describe "lock for migrations" do
    setup do
      put_test_adapter_config(test_process: self())
    end

    test "on up" do
      assert up(TestRepo, 9, Migration, log: false) == :ok
      assert_receive {:lock_for_migrations, _}

      assert up(TestRepo, 10, NoLockMigration, log: false) == :ok
      refute_received {:lock_for_migrations, _}
    end

    test "on down" do
      assert down(TestRepo, 1, Migration, log: false) == :ok
      assert_receive {:lock_for_migrations, _}

      assert down(TestRepo, 2, NoLockMigration, log: false) == :ok
      refute_received {:lock_for_migrations, _}
    end

    test "on run" do
      in_tmp fn path ->
        create_migration "13_sample.exs"
        assert run(TestRepo, path, :up, all: true, log: false) == [13]
        # One lock for fetching versions, another for running
        assert_receive {:lock_for_migrations, _}
        assert_receive {:lock_for_migrations, _}

        create_migration "14_sample.exs", [:disable_migration_lock]
        assert run(TestRepo, path, :up, all: true, log: false) == [14]
        # One lock for fetching versions, another from running
        assert_receive {:lock_for_migrations, _}
        refute_received {:lock_for_migrations, _}
      end
    end
  end

  describe "run" do
    test "expects files starting with an integer" do
      in_tmp fn path ->
        create_migration "a_sample.exs"
        assert run(TestRepo, path, :up, all: true, log: false) == []
      end
    end

    test "fails if there is no migration in file" do
      in_tmp fn path ->
        File.write! "13_sample.exs", ":ok"
        assert_raise Ecto.MigrationError, "file 13_sample.exs does not define an Ecto.Migration", fn ->
          run(TestRepo, path, :up, all: true, log: false)
        end
      end
    end

    test "fails if there are duplicated versions" do
      in_tmp fn path ->
        create_migration "13_hello.exs"
        create_migration "13_other.exs"
        assert_raise Ecto.MigrationError, "migrations can't be executed, migration version 13 is duplicated", fn ->
          run(TestRepo, path, :up, all: true, log: false)
        end
      end
    end

    test "fails if there are duplicated name" do
      in_tmp fn path ->
        create_migration "13_hello.exs"
        create_migration "14_hello.exs"
        assert_raise Ecto.MigrationError, "migrations can't be executed, migration name hello is duplicated", fn ->
          run(TestRepo, path, :up, all: true, log: false)
        end
      end
    end

    test "upwards migrations skips migrations that are already up" do
      in_tmp fn path ->
        create_migration "1_sample.exs"
        assert run(TestRepo, path, :up, all: true, log: false) == []
      end
    end

    test "downwards migrations skips migrations that are already down" do
      in_tmp fn path ->
        create_migration "1_sample1.exs"
        create_migration "4_sample2.exs"
        assert run(TestRepo, path, :down, all: true, log: false) == [1]
      end
    end

    test "stepwise migrations stop before all have been run" do
      in_tmp fn path ->
        create_migration "13_step_premature_end1.exs"
        create_migration "14_step_premature_end2.exs"
        assert run(TestRepo, path, :up, step: 1, log: false) == [13]
      end
    end

    test "stepwise migrations stop at the number of available migrations" do
      in_tmp fn path ->
        create_migration "13_step_to_the_end1.exs"
        create_migration "14_step_to_the_end2.exs"
        assert run(TestRepo, path, :up, step: 2, log: false) == [13, 14]
      end
    end

    test "stepwise migrations stop even if asked to exceed available" do
      in_tmp fn path ->
        create_migration "13_step_past_the_end1.exs"
        create_migration "14_step_past_the_end2.exs"
        assert run(TestRepo, path, :up, step: 3, log: false) == [13, 14]
      end
    end

    test "version migrations stop before all have been run" do
      in_tmp fn path ->
        create_migration "13_version_premature_end1.exs"
        create_migration "14_version_premature_end2.exs"
        assert run(TestRepo, path, :up, to: 13, log: false) == [13]
      end
    end

    test "version migrations stop at the number of available migrations" do
      in_tmp fn path ->
        create_migration "13_version_to_the_end1.exs"
        create_migration "14_version_to_the_end2.exs"
        assert run(TestRepo, path, :up, to: 14, log: false) == [13, 14]
      end
    end

    test "version migrations stop even if asked to exceed available" do
      in_tmp fn path ->
        create_migration "13_version_past_the_end1.exs"
        create_migration "14_version_past_the_end2.exs"
        assert run(TestRepo, path, :up, to: 15, log: false) == [13, 14]
      end
    end

    test "version migrations work inside directories" do
      in_tmp fn path ->
        File.mkdir_p!("foo")
        create_migration "foo/13_version_in_dir.exs"
        assert run(TestRepo, Path.join(path, "foo"), :up, to: 15, log: false) == [13]
      end
    end
  end

  describe "migrations" do
    test "give the up and down migration status" do
      in_tmp fn path ->
        create_migration "1_up_migration_1.exs"
        create_migration "2_up_migration_2.exs"
        create_migration "3_up_migration_3.exs"
        create_migration "4_down_migration_1.exs"
        create_migration "5_down_migration_2.exs"

        expected_result = [
          {:up, 1, "up_migration_1"},
          {:up, 2, "up_migration_2"},
          {:up, 3, "up_migration_3"},
          {:down, 4, "down_migration_1"},
          {:down, 5, "down_migration_2"}
        ]

        assert migrations(TestRepo, path) == expected_result
      end
    end

    test "are picked up from subdirs" do
      in_tmp(fn path ->
        File.mkdir_p!("foo")

        create_migration "foo/6_up_migration_1.exs"
        create_migration "7_up_migration_2.exs"
        create_migration "8_up_migration_3.exs"

        assert run(TestRepo, path, :up, all: true, log: false) == [6, 7, 8]
      end)
    end

    test "give the migration status while file is deleted" do
      in_tmp fn path ->
        create_migration "1_up_migration_1.exs"
        create_migration "2_up_migration_2.exs"
        create_migration "3_up_migration_3.exs"
        create_migration "4_down_migration_1.exs"

        File.rm("2_up_migration_2.exs")

        expected_result = [
          {:up, 1, "up_migration_1"},
          {:up, 2, "** FILE NOT FOUND **"},
          {:up, 3, "up_migration_3"},
          {:down, 4, "down_migration_1"},
        ]

        assert migrations(TestRepo, path) == expected_result
      end
    end

    test "run inside a transaction if the adapter supports ddl transactions" do
      capture_log fn ->
        put_test_adapter_config(supports_ddl_transaction?: true, test_process: self())
        up(TestRepo, 0, ChangeMigration)
        assert_receive {:transaction, _}
      end
    end

    test "can be forced to run outside a transaction" do
      capture_log fn ->
        put_test_adapter_config(supports_ddl_transaction?: true, test_process: self())
        up(TestRepo, 0, NoTransactionMigration)
        refute_received {:transaction, _}
      end
    end

    test "does not run inside a transaction if the adapter does not support ddl transactions" do
      capture_log fn ->
        put_test_adapter_config(supports_ddl_transaction?: false, test_process: self())
        up(TestRepo, 0, ChangeMigration)
        refute_received {:transaction, _}
      end
    end
  end

  describe "alternate migration source format" do
    test "fails if there is no migration in file" do
      assert_raise Ecto.MigrationError, "module Ecto.MigratorTest.EmptyModule is not an Ecto.Migration", fn ->
        run(TestRepo, [{13, EmptyModule}], :up, all: true, log: false)
      end
    end

    test "fails if the module does not define migrations" do
      assert_raise Ecto.MigrationError, "Ecto.MigratorTest.InvalidMigration does not implement a `up/0` or `change/0` function", fn ->
        run(TestRepo, [{13, InvalidMigration}], :up, all: true, log: false)
      end
    end

    test "fails if there are duplicated versions" do
      assert_raise Ecto.MigrationError, "migrations can't be executed, migration version 13 is duplicated", fn ->
        run(TestRepo, [{13, ChangeMigration}, {13, UpDownMigration}], :up, all: true, log: false)
      end
    end

    test "fails if there are duplicated name" do
      assert_raise Ecto.MigrationError, "migrations can't be executed, migration name Elixir.Ecto.MigratorTest.ChangeMigration is duplicated", fn ->
        run(TestRepo, [{13, ChangeMigration}, {14, ChangeMigration}], :up, all: true, log: false)
      end
    end

    test "upwards migrations skips migrations that are already up" do
      assert run(TestRepo, [{1, ChangeMigration}], :up, all: true, log: false) == []
    end

    test "downwards migrations skips migrations that are already down" do
      assert run(TestRepo, [{1, ChangeMigration}, {4, UpDownMigration}], :down, all: true, log: false) == [1]
    end

    test "stepwise migrations stop before all have been run" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, step: 1, log: false) == [13]
    end

    test "stepwise migrations stop at the number of available migrations" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, step: 2, log: false) == [13, 14]
    end

    test "stepwise migrations stop even if asked to exceed available" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, step: 3, log: false) == [13, 14]
    end

    test "version migrations stop before all have been run" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, to: 13, log: false) == [13]
    end

    test "version migrations stop at the number of available migrations" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, to: 14, log: false) == [13, 14]
    end

    test "version migrations stop even if asked to exceed available" do
      assert run(TestRepo, [{13, ChangeMigration}, {14, UpDownMigration}], :up, to: 15, log: false) == [13, 14]
    end
  end

  describe "migration callbacks" do
    setup do
      put_test_adapter_config(supports_ddl_transaction?: true)
    end

    test "both run when in a transaction going up" do
      log = capture_log(fn ->
        assert up(TestRepo, 10, MigrationWithCallbacks) == :ok
      end)

      assert log =~ "after_begin"
      assert log =~ "before_commit"
    end

    test "are both run in a transaction going down" do
      assert up(TestRepo, 10, MigrationWithCallbacks, log: false) == :ok

      log = capture_log(fn ->
        assert down(TestRepo, 10, MigrationWithCallbacks) == :ok
      end)

      assert log =~ "after_begin_down"
      assert log =~ "before_commit_down"
    end

    test "are not run when the transaction is disabled" do
      log = capture_log(fn ->
        assert up(TestRepo, 10, MigrationWithCallbacksAndNoTransaction) == :ok
      end)

      refute log =~ "after_begin"
      refute log =~ "before_commit"
    end
  end

  describe "with_repo" do
    defmodule Repo do
      def start_link(opts) do
        assert opts[:pool_size] == 2
        Process.get(:start_link)
      end

      def stop() do
        Process.put(:stopped, true)
      end

      def __adapter__ do
        EctoSQL.TestAdapter
      end

      def config do
        [priv: Process.get(:priv), otp_app: :ecto_sql]
      end
    end

    test "starts and stops repo" do
      Process.put(:start_link, {:ok, self()})
      assert with_repo(Repo, fn Repo -> :one end) == {:ok, :one, []}
      assert Process.get(:stopped)
    end

    test "runs with existing repo" do
      Process.put(:start_link, {:error, {:already_started, self()}})
      assert with_repo(Repo, fn Repo -> :two end) == {:ok, :two, []}
      refute Process.get(:stopped)
    end

    test "handles errors" do
      Process.put(:start_link, {:error, :oops})
      assert with_repo(Repo, fn Repo -> raise "never invoked" end) == {:error, :oops}
      refute Process.get(:stopped)
    end
  end
end
