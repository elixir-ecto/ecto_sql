Code.require_file("../support/file_helpers.exs", __DIR__)

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
    Keyword.merge(params(),
      username: "randomuser",
      password: "password1234"
    )
  end

  def drop_database do
    run_mysql("DROP DATABASE #{params()[:database]};")
  end

  def create_database(grant_privileges_to \\ nil) do
    run_mysql("CREATE DATABASE #{params()[:database]};")
    if grant_privileges_to do
      run_mysql("GRANT ALL PRIVILEGES ON #{params()[:database]}.* to #{grant_privileges_to}")
    end
  end

  def create_posts do
    run_mysql("CREATE TABLE posts (title varchar(20));", ["-D", params()[:database]])
  end

  def run_mysql(sql, args \\ []) do
    params = params()
    env = if password = params[:password], do: [{"MYSQL_PWD", password}], else: []

    args = [
      "-u",
      params[:username],
      "--host",
      params[:hostname],
      "--port",
      to_string(params[:port] || 3306),
      "-e",
      sql | args
    ]

    System.cmd("mysql", args, env: env)
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

  test "storage up with unprivileged user with access to the database" do
    unprivileged_params = Keyword.merge(params(),
      username: "unprivileged",
      password: "pass"
    )
    run_mysql("CREATE USER unprivileged IDENTIFIED BY 'pass'")
    refute Ecto.Adapters.MyXQL.storage_up(unprivileged_params) == :ok
    create_database("unprivileged")
    assert Ecto.Adapters.MyXQL.storage_up(unprivileged_params) == {:error, :already_up}
  after
    run_mysql("DROP USER unprivileged")
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

    {:error, _} =
      Ecto.Adapters.MyXQL.structure_load(tmp_path(), [dump_path: dump_path] ++ params())

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

  test "storage status is up when database is created" do
    create_database()
    assert :up == Ecto.Adapters.MyXQL.storage_status(params())
  after
    drop_database()
  end

  test "storage status is down when database is not created" do
    create_database()
    drop_database()
    assert :down == Ecto.Adapters.MyXQL.storage_status(params())
  end

  test "storage status is an error when wrong credentials are passed" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             assert {:error, _} = Ecto.Adapters.MyXQL.storage_status(wrong_params())
           end) =~ "(1045) (ER_ACCESS_DENIED_ERROR)"
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

  test "structure dump_cmd" do
    num = @base_migration + System.unique_integer([:positive])
    :ok = Ecto.Migrator.up(PoolRepo, num, Migration, log: false)

    assert {output, 0} =
             Ecto.Adapters.MyXQL.dump_cmd(
               ["--no-create-info", "--tables", "schema_migrations"],
               [],
               PoolRepo.config()
             )

    assert output =~ "INSERT INTO `schema_migrations` VALUES ("
  end
end
