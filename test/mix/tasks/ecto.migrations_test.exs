defmodule Mix.Tasks.Ecto.MigrationsTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Migrations, only: [run: 3]
  import Support.FileHelpers

  migrations_path = Path.join([tmp_path(), inspect(Ecto.Migrations), "migrations"])

  setup do
    File.mkdir_p!(unquote(migrations_path))
    :ok
  end

  defmodule Repo do
    def start_link(_) do
      Process.put(:started, true)

      Task.start_link(fn ->
        Process.flag(:trap_exit, true)

        receive do
          {:EXIT, _, :normal} -> :ok
        end
      end)
    end

    def stop() do
      :ok
    end

    def __adapter__ do
      EctoSQL.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Migrations)}", otp_app: :ecto_sql]
    end
  end

  test "displays the up and down status for the default repo" do
    Application.put_env(:ecto_sql, :ecto_repos, [Repo])

    migrations = fn _, _, _ ->
      [
        {:up, 0, "up_migration_0"},
        {:up, 20_160_000_000_001, "up_migration_1"},
        {:up, 20_160_000_000_002, "up_migration_2"},
        {:up, 20_160_000_000_003, "up_migration_3"},
        {:down, 20_160_000_000_004, "down_migration_1"},
        {:down, 20_160_000_000_005, "down_migration_2"}
      ]
    end

    expected_output = """

    Repo: Mix.Tasks.Ecto.MigrationsTest.Repo

      Status    Migration ID    Migration Name
    --------------------------------------------------
      up        0               up_migration_0
      up        20160000000001  up_migration_1
      up        20160000000002  up_migration_2
      up        20160000000003  up_migration_3
      down      20160000000004  down_migration_1
      down      20160000000005  down_migration_2
    """

    run([], migrations, fn i -> assert(i == expected_output) end)
  end

  test "migrations displays the up and down status for any given repo" do
    migrations = fn _, _, _ ->
      [
        {:up, 20_160_000_000_001, "up_migration_1"},
        {:down, 20_160_000_000_002, "down_migration_1"}
      ]
    end

    expected_output = """

    Repo: Mix.Tasks.Ecto.MigrationsTest.Repo

      Status    Migration ID    Migration Name
    --------------------------------------------------
      up        20160000000001  up_migration_1
      down      20160000000002  down_migration_1
    """

    run(["-r", to_string(Repo)], migrations, fn i -> assert(i == expected_output) end)
  end

  test "does not run from _build" do
    Application.put_env(:ecto_sql, :ecto_repos, [Repo])

    migrations = fn repo, [path], _opts ->
      assert repo == Repo
      refute path =~ ~r/_build/
      []
    end

    run([], migrations, fn _ -> :ok end)
  end

  test "uses custom paths" do
    path1 = Path.join([unquote(tmp_path()), inspect(Ecto.Migrate), "migrations_1"])
    path2 = Path.join([unquote(tmp_path()), inspect(Ecto.Migrate), "migrations_2"])
    File.mkdir_p!(path1)
    File.mkdir_p!(path2)

    run(
      ["-r", to_string(Repo), "--migrations-path", path1, "--migrations-path", path2],
      fn Repo, [^path1, ^path2], _opts -> [] end,
      fn _ -> :ok end
    )
  end

  describe "migrations_paths config" do
    defmodule RepoWithMigrationsPaths do
      def start_link(_) do
        Process.put(:started, true)

        Task.start_link(fn ->
          Process.flag(:trap_exit, true)

          receive do
            {:EXIT, _, :normal} -> :ok
          end
        end)
      end

      def stop do
        :ok
      end

      def __adapter__ do
        EctoSQL.TestAdapter
      end

      def config do
        migrations_path_1 =
          Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_1"])

        migrations_path_2 =
          Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_2"])

        [
          priv: "tmp/#{inspect(Ecto.Migrations)}",
          otp_app: :ecto_sql,
          migrations_paths: [
            Path.relative_to(migrations_path_1, File.cwd!()),
            Path.relative_to(migrations_path_2, File.cwd!())
          ]
        ]
      end
    end

    setup do
      path1 = Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_1"])
      path2 = Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_2"])
      File.mkdir_p!(path1)
      File.mkdir_p!(path2)
      :ok
    end

    test "uses migrations_paths from repo config when no --migrations-path flag" do
      path1 = Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_1"])
      path2 = Path.join([tmp_path(), inspect(Ecto.Migrations), "configured_migrations_2"])

      migrations = fn repo, paths, _opts ->
        assert repo == RepoWithMigrationsPaths
        assert length(paths) == 2
        assert Path.expand(Enum.at(paths, 0)) == Path.expand(path1)
        assert Path.expand(Enum.at(paths, 1)) == Path.expand(path2)

        [
          {:up, 20_230_000_000_001, "migration_from_path_1"},
          {:down, 20_230_000_000_002, "migration_from_path_2"}
        ]
      end

      expected_output = """

      Repo: Mix.Tasks.Ecto.MigrationsTest.RepoWithMigrationsPaths

        Status    Migration ID    Migration Name
      --------------------------------------------------
        up        20230000000001  migration_from_path_1
        down      20230000000002  migration_from_path_2
      """

      run(["-r", to_string(RepoWithMigrationsPaths)], migrations, fn output ->
        assert output == expected_output
      end)

      assert Process.get(:started)
    end

    test "command-line --migrations-path takes precedence over repo config" do
      custom_path = Path.join([tmp_path(), inspect(Ecto.Migrations), "cli_migrations"])
      File.mkdir_p!(custom_path)

      migrations = fn repo, [path], _opts ->
        assert repo == RepoWithMigrationsPaths
        assert path == custom_path

        [
          {:up, 20_230_000_000_003, "cli_migration_1"},
          {:down, 20_230_000_000_004, "cli_migration_2"}
        ]
      end

      expected_output = """

      Repo: Mix.Tasks.Ecto.MigrationsTest.RepoWithMigrationsPaths

        Status    Migration ID    Migration Name
      --------------------------------------------------
        up        20230000000003  cli_migration_1
        down      20230000000004  cli_migration_2
      """

      run(
        ["-r", to_string(RepoWithMigrationsPaths), "--migrations-path", custom_path],
        migrations,
        fn output ->
          assert output == expected_output
        end
      )

      assert Process.get(:started)
    end
  end
end
