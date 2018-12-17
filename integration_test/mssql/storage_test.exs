Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case

  @moduletag :capture_log
  # @base_migration 5_000_000

  # import Support.FileHelpers
  alias Ecto.Adapters.MsSql
  # alias Ecto.Integration.{PoolRepo, TestRepo}

  def params do
    url = Application.get_env(:ecto_sql, :mssql_test_url) <> "/storage_mgt"
    [log: false] ++ Ecto.Repo.Supervisor.parse_url(url)
  end

  def wrong_params() do
    Keyword.merge params(),
      [username: "randomuser",
       password: "password1234"]
  end

  def drop_database do
    database = params()[:database]
    run_sqlcmd("DROP DATABASE [#{database}];", ["-d", "master"])
  end

  def create_database do
    database = params()[:database]
    run_sqlcmd("CREATE DATABASE [#{database}];", ["-d", "master"])
  end

  def create_posts do
    run_sqlcmd("CREATE TABLE posts (title nvarchar(20));", ["-d", params()[:database]])
  end

  def run_sqlcmd(sql, args \\ []) do
    params = params()
    args = [
      "-U", params[:username],
      "-P", params[:password],
      "-S", params[:hostname],
      "-Q", ~s(#{sql}) | args]
    System.cmd "sqlcmd", args
  end

  test "storage up (twice in a row)" do
    assert :ok == MsSql.storage_up(params())
    assert {:error, :already_up} == MsSql.storage_up(params())
  after
    drop_database()
  end

  test "storage down (twice in a row)" do
    {_, 0} = create_database()
    assert :ok == MsSql.storage_down(params())
    assert {:error, :already_down} == MsSql.storage_down(params())
  end

  test "storage up and down (wrong credentials)" do
    refute :ok == MsSql.storage_up(wrong_params())
    {_, 0} = create_database()
    refute :ok == MsSql.storage_down(wrong_params())
  after
    drop_database()
  end

  # test "structure dump and load" do
  #   create_database()
  #   create_posts()

  #   # Default path
  #   {:ok, _} = MsSql.structure_dump(tmp_path(), params())
  #   dump = File.read!(Path.join(tmp_path(), "structure.sql"))

  #   drop_database()
  #   create_database()

  #   # Load custom
  #   dump_path = Path.join(tmp_path(), "custom.sql")
  #   File.rm(dump_path)
  #   {:error, _} = MsSql.structure_load(tmp_path(), [dump_path: dump_path] ++ params())

  #   # Dump custom
  #   {:ok, _} = MsSql.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
  #   assert strip_timestamp(dump) != strip_timestamp(File.read!(dump_path))

  #   # Load original
  #   {:ok, _} = MsSql.structure_load(tmp_path(), params())

  #   {:ok, _} = MsSql.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
  #   assert strip_timestamp(dump) == strip_timestamp(File.read!(dump_path))
  # after
  #   drop_database()
  # end

  # defmodule Migration do
  #   use Ecto.Migration
  #   def change, do: :ok
  # end

  # test "structure dump and load with migrations table" do
  #   num = @base_migration + System.unique_integer([:positive])
  #   :ok = Ecto.Migrator.up(PoolRepo, num, Migration, log: false)
  #   {:ok, path} = MsSql.structure_dump(tmp_path(), TestRepo.config())
  #   contents = File.read!(path)
  #   assert contents =~ "INSERT INTO [dbo].[schema_migrations] (version) VALUES ("
  # end

  # defp strip_timestamp(dump) do
  #   dump
  #   |> String.split("\n")
  #   |> Enum.reject(&String.contains?(&1, "completed on"))
  #   |> Enum.join("\n")
  # end
end
