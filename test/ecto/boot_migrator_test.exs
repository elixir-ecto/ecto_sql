defmodule Ecto.BootMigratorTest do
  use ExUnit.Case

  import Support.FileHelpers

  @migrations_path Path.join([tmp_path(), inspect(Ecto.Migrate), "migrations"])

  setup do
    File.mkdir_p!(@migrations_path)
    :ok
  end

  defmodule Repo do
    def start_link(_) do
      Process.put(:started, true)
      Task.start_link fn ->
        Process.flag(:trap_exit, true)
        receive do
          {:EXIT, _, :normal} -> :ok
        end
      end
    end

    def stop do
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
      Process.put(:already_started, true)
      {:error, {:already_started, :whatever}}
    end

    def stop do
      raise "should not be called"
    end

    def __adapter__ do
      EctoSQL.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Migrate)}", otp_app: :ecto_sql]
    end
  end

  test "runs the migrator with app_repo config" do
    migrator = fn repo, _, _ ->
      assert Repo == repo
      Process.put(:migrated, true)
      []
    end

    assert :ignore = Ecto.Migration.BootMigrator.init([repos: [Repo], migrator: migrator])

    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "skip is set" do
    migrator = fn repo, _, _ ->
      assert Repo == repo
      Process.put(:migrated, true)
      []
    end

    assert :ignore = Ecto.Migration.BootMigrator.init([repos: [Repo], migrator: migrator, skip: true])

    refute Process.get(:migrated)
  end

  test "SKIP_MIGRATIONS is set" do
    System.put_env("SKIP_MIGRATIONS", "true")
    migrator = fn repo, _, _ ->
      assert Repo == repo
      Process.put(:migrated, true)
      []
    end

    assert :ignore = Ecto.Migration.BootMigrator.init([repos: [Repo], migrator: migrator])

    refute Process.get(:migrated)

  after
    System.delete_env("SKIP_MIGRATIONS")
  end

  test "migrations fail" do
    migrator = fn repo, _, _ ->
      assert Repo == repo
      raise "boom"
      []
    end

    assert_raise RuntimeError, fn ->
      Ecto.Migration.BootMigrator.init([repos: [Repo], migrator: migrator])
    end
  end
end
