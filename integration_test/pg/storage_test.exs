Code.require_file("../support/file_helpers.exs", __DIR__)

defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case

  @moduletag :capture_log
  @base_migration 5_000_000

  import Support.FileHelpers
  alias Ecto.Adapters.Postgres
  alias Ecto.Integration.{PoolRepo, TestRepo}

  def params do
    # Pass log false to ensure we can still create/drop.
    url = Application.get_env(:ecto_sql, :pg_test_url) <> "/storage_mgt"
    [log: false] ++ Ecto.Repo.Supervisor.parse_url(url)
  end

  def wrong_params do
    Keyword.merge(params(),
      username: "randomuser",
      password: "password1234"
    )
  end

  def drop_database do
    run_psql("DROP DATABASE #{params()[:database]};")
  end

  def create_database(owner \\ nil) do
    query = "CREATE DATABASE #{params()[:database]}"
    query = if owner do
      query <> " OWNER #{owner};"
    else
      query <> ";"
    end
    run_psql(query)
  end

  def create_posts do
    run_psql("CREATE TABLE posts (title varchar(20));", [params()[:database]])
  end

  def run_psql(sql, args \\ []) do
    params = params()
    env = if password = params[:password], do: [{"PGPASSWORD", password}], else: []

    args = [
      "-U",
      params[:username],
      "--host",
      params[:hostname],
      "-p",
      to_string(params[:port] || 5432),
      "-c",
      sql | args
    ]

    System.cmd("psql", args, env: env)
  end

  test "storage up (twice in a row)" do
    assert Postgres.storage_up(params()) == :ok
    assert Postgres.storage_up(params()) == {:error, :already_up}
  after
    drop_database()
  end

  test "storage down (twice in a row)" do
    create_database()
    assert Postgres.storage_down(params()) == :ok
    assert Postgres.storage_down(params()) == {:error, :already_down}
  end

  test "storage up and down (wrong credentials)" do
    refute Postgres.storage_up(wrong_params()) == :ok
    create_database()
    refute Postgres.storage_down(wrong_params()) == :ok
  after
    drop_database()
  end

  test "storage up with unprivileged user with access to the database" do
    unprivileged_params = Keyword.merge(params(),
      username: "unprivileged",
      password: "pass"
    )
    run_psql("CREATE USER unprivileged WITH NOCREATEDB PASSWORD 'pass'")
    refute Postgres.storage_up(unprivileged_params) == :ok
    create_database("unprivileged")
    assert Postgres.storage_up(unprivileged_params) == {:error, :already_up}
  after
    run_psql("DROP USER unprivileged")
    drop_database()
  end

  test "structure dump and load" do
    create_database()
    create_posts()

    # Default path
    {:ok, _} = Postgres.structure_dump(tmp_path(), params())
    dump = File.read!(Path.join(tmp_path(), "structure.sql"))

    drop_database()
    create_database()

    # Load custom
    dump_path = Path.join(tmp_path(), "custom.sql")
    File.rm(dump_path)
    {:error, _} = Postgres.structure_load(tmp_path(), [dump_path: dump_path] ++ params())

    # Dump custom
    {:ok, _} = Postgres.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert dump != File.read!(dump_path)

    # Load original
    {:ok, _} = Postgres.structure_load(tmp_path(), params())

    {:ok, _} = Postgres.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert dump == File.read!(dump_path)
  after
    drop_database()
  end

  test "structure load will fail on SQL errors" do
    File.mkdir_p!(tmp_path())
    error_path = Path.join(tmp_path(), "error.sql")
    File.write!(error_path, "DO $$ BEGIN RAISE EXCEPTION 'failing SQL'; END $$;")

    {:error, message} =
      Postgres.structure_load(tmp_path(), [dump_path: error_path] ++ TestRepo.config())

    assert message =~ ~r/ERROR.*failing SQL/
  end

  defmodule Migration do
    use Ecto.Migration
    def change, do: :ok
  end

  test "structure dump and load with migrations table" do
    num = @base_migration + System.unique_integer([:positive])
    :ok = Ecto.Migrator.up(PoolRepo, num, Migration, log: false)
    {:ok, path} = Postgres.structure_dump(tmp_path(), TestRepo.config())
    contents = File.read!(path)
    assert contents =~ ~s[INSERT INTO public."schema_migrations" (version) VALUES]
  end

  test "storage status is up when database is created" do
    create_database()
    assert :up == Postgres.storage_status(params())
  after
    drop_database()
  end

  test "storage status is down when database is not created" do
    create_database()
    drop_database()
    assert :down == Postgres.storage_status(params())
  end

  test "storage status is an error when wrong credentials are passed" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             assert {:error, _} = Postgres.storage_status(wrong_params())
           end) =~ ~r"FATAL (28000|28P01)"
  end

  test "structure dump_cmd" do
    num = @base_migration + System.unique_integer([:positive])
    :ok = Ecto.Migrator.up(PoolRepo, num, Migration, log: false)

    assert {"--\n-- PostgreSQL database dump\n--\n\n--" <> _rest, 0} =
             Postgres.dump_cmd(
               ["--data-only", "--table", "schema_migrations"],
               [],
               PoolRepo.config()
             )
  end
end
