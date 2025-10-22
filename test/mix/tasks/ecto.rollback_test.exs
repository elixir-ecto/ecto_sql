defmodule Mix.Tasks.Ecto.RollbackTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Rollback, only: [run: 2]
  import Support.FileHelpers

  @migrations_path Path.join([tmp_path(), inspect(Ecto.Migrate), "migrations"])

  setup do
    File.mkdir_p!(@migrations_path)
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
      [priv: "tmp/#{inspect(Ecto.Migrate)}", otp_app: :ecto_sql]
    end
  end

  defmodule StartedRepo do
    def start_link(_) do
      {:error, {:already_started, :whatever}}
    end

    def stop() do
      raise "should not be called"
    end

    def __adapter__ do
      EctoSQL.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Migrate)}", otp_app: :ecto_sql]
    end
  end

  test "runs the migrator after starting repo" do
    run(["-r", to_string(Repo)], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator with already started repo" do
    run(["-r", to_string(StartedRepo)], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run(["-r", to_string(Repo), "--prefix", "foo"], fn repo, [path], direction, opts ->
      assert repo == Repo
      refute path =~ ~r/_build/
      assert direction == :down
      assert opts[:step] == 1
      assert opts[:prefix] == "foo"
      []
    end)

    assert Process.get(:started)
  end

  test "raises when migrations path does not exist" do
    File.rm_rf!(@migrations_path)

    assert_raise Mix.Error, fn ->
      run(["-r", to_string(Repo)], fn _, _, _, _ -> [] end)
    end

    assert !Process.get(:started)
  end

  test "uses custom paths" do
    path1 = Path.join([unquote(tmp_path()), inspect(Ecto.Migrate), "migrations_1"])
    path2 = Path.join([unquote(tmp_path()), inspect(Ecto.Migrate), "migrations_2"])
    File.mkdir_p!(path1)
    File.mkdir_p!(path2)

    run(
      ["-r", to_string(Repo), "--migrations-path", path1, "--migrations-path", path2],
      fn Repo, [^path1, ^path2], _, _ -> [] end
    )
  end

  test "runs the migrator with --to_exclusive" do
    run(["-r", to_string(Repo), "--to-exclusive", "12345"], fn repo, [path], direction, opts ->
      assert repo == Repo
      refute path =~ ~r/_build/
      assert direction == :down
      assert opts == [repo: "Elixir.Mix.Tasks.Ecto.RollbackTest.Repo", to_exclusive: 12345]
      []
    end)

    assert Process.get(:started)
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
          Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_1"])

        migrations_path_2 =
          Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_2"])

        [
          priv: "tmp/#{inspect(Ecto.Migrate)}",
          otp_app: :ecto_sql,
          migrations_paths: [
            Path.relative_to(migrations_path_1, File.cwd!()),
            Path.relative_to(migrations_path_2, File.cwd!())
          ]
        ]
      end
    end

    setup do
      path1 = Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_1"])
      path2 = Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_2"])
      File.mkdir_p!(path1)
      File.mkdir_p!(path2)
      :ok
    end

    test "uses migrations_paths from repo config when no --migrations-path flag" do
      path1 = Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_1"])
      path2 = Path.join([tmp_path(), inspect(Ecto.Migrate), "configured_migrations_2"])

      run(["-r", to_string(RepoWithMigrationsPaths)], fn repo, paths, direction, _opts ->
        assert repo == RepoWithMigrationsPaths
        assert length(paths) == 2
        assert Path.expand(Enum.at(paths, 0)) == Path.expand(path1)
        assert Path.expand(Enum.at(paths, 1)) == Path.expand(path2)
        assert direction == :down
        []
      end)

      assert Process.get(:started)
    end

    test "command-line --migrations-path takes precedence over repo config" do
      custom_path = Path.join([tmp_path(), inspect(Ecto.Migrate), "cli_migrations"])
      File.mkdir_p!(custom_path)

      run(
        ["-r", to_string(RepoWithMigrationsPaths), "--migrations-path", custom_path],
        fn repo, [path], direction, _opts ->
          assert repo == RepoWithMigrationsPaths
          assert path == custom_path
          assert direction == :down
          []
        end
      )

      assert Process.get(:started)
    end
  end
end
