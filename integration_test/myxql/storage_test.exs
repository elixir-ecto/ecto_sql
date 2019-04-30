Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case

  @moduletag :capture_log
  @base_migration 5_000_000

  import Support.FileHelpers
  alias Ecto.Integration.{PoolRepo, TestRepo}

  def params do
    # Pass log false to ensure we can still create/drop.
    url = Application.get_env(:ecto_sql, :mysql_test_url) <> "/storage_mgt"
    [log: false] ++ Ecto.Repo.Supervisor.parse_url(url)
  end

  def wrong_params do
    Keyword.merge params(),
      [username: "randomuser",
       password: "password1234"]
  end

  def drop_database do
    run_mysql("DROP DATABASE #{params()[:database]};")
  end

  def create_database do
    run_mysql("CREATE DATABASE #{params()[:database]};")
  end

  def create_posts do
    run_mysql("CREATE TABLE posts (title varchar(20));", ["-D", params()[:database]])
  end

  def run_mysql(sql, args \\ []) do
    args = ["-u", params()[:username], "-e", sql | args]
    System.cmd "mysql", args
  end

  test "storage up (twice in a row)" do
    assert Ecto.Adapters.MyXQL.storage_up(params()) == :ok
    assert Ecto.Adapters.MyXQL.storage_up(params()) == {:error, :already_up}
  after
    drop_database()
  end

  test "storage down (twice in a row)" do
    create_database()
    assert Ecto.Adapters.MyXQL.storage_down(params()) == :ok
    assert Ecto.Adapters.MyXQL.storage_down(params()) == {:error, :already_down}
  end

  test "storage up and down (wrong credentials)" do
    refute Ecto.Adapters.MyXQL.storage_up(wrong_params()) == :ok
    create_database()
    refute Ecto.Adapters.MyXQL.storage_down(wrong_params()) == :ok
  after
    drop_database()
  end

  test "structure dump and load" do
    create_database()
    create_posts()

    # Default path
    {:ok, _} = Ecto.Adapters.MyXQL.structure_dump(tmp_path(), params())
    dump = File.read!(Path.join(tmp_path(), "structure.sql"))

    drop_database()
    create_database()

    # Load custom
    dump_path = Path.join(tmp_path(), "custom.sql")
    File.rm(dump_path)
    {:error, _} = Ecto.Adapters.MyXQL.structure_load(tmp_path(), [dump_path: dump_path] ++ params())

    # Dump custom
    {:ok, _} = Ecto.Adapters.MyXQL.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert strip_timestamp(dump) != strip_timestamp(File.read!(dump_path))

    # Load original
    {:ok, _} = Ecto.Adapters.MyXQL.structure_load(tmp_path(), params())

    {:ok, _} = Ecto.Adapters.MyXQL.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert strip_timestamp(dump) == strip_timestamp(File.read!(dump_path))
  after
    drop_database()
  end

  defmodule Migration do
    use Ecto.Migration
    def change, do: :ok
  end

  test "structure dump and load with migrations table" do
    num = @base_migration + System.unique_integer([:positive])
    :ok = Ecto.Migrator.up(PoolRepo, num, Migration, log: false)
    {:ok, path} = Ecto.Adapters.MyXQL.structure_dump(tmp_path(), TestRepo.config())
    contents = File.read!(path)
    assert contents =~ "INSERT INTO `schema_migrations` (version) VALUES ("
  end

  defp strip_timestamp(dump) do
    dump
    |> String.split("\n")
    |> Enum.reject(&String.contains?(&1, "completed on"))
    |> Enum.join("\n")
  end
end
