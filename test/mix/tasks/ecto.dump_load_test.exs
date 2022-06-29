defmodule Mix.Tasks.Ecto.DumpLoadTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ecto.{Load, Dump}

  # Mocked adapters

  defmodule Adapter do
    @behaviour Ecto.Adapter
    @behaviour Ecto.Adapter.Structure

    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def checkout(_, _, _), do: raise "not implemented"
    def checked_out?(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: {:ok, []}

    def init(_opts) do
      child_spec = Supervisor.child_spec({Task, fn -> :timer.sleep(:infinity) end}, [])
      {:ok, child_spec, %{}}
    end

    def structure_dump(_, _), do: Process.get(:structure_dump) || raise "no structure_dump"
    def structure_load(_, _), do: Process.get(:structure_load) || raise "no structure_load"
    def dump_cmd(_, _, _), do: Process.get(:dump_cmd) || raise "no dump_cmd"
  end

  defmodule NoStructureAdapter do
    @behaviour Ecto.Adapter
    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def init(_), do: raise "not implemented"
    def checkout(_, _, _), do: raise "not implemented"
    def checked_out?(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: raise "not implemented"
  end

  # Mocked repos

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: Adapter
  end

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: Adapter
  end

  defmodule NoStructureRepo do
    use Ecto.Repo, otp_app: :ecto_sql, adapter: NoStructureAdapter
  end

  setup do
    Application.put_env(:ecto_sql, __MODULE__.Repo, [])
    Application.put_env(:ecto_sql, __MODULE__.NoStructureRepo, [])
  end

  ## Dump

  test "runs the adapter structure_dump" do
    Process.put(:structure_dump, {:ok, "foo"})
    Dump.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been dumped to foo"]}
  end

  test "runs the adapter structure_dump for migration_repo" do
    Application.put_env(:ecto_sql, Repo, [migration_repo: MigrationRepo])

    Process.put(:structure_dump, {:ok, "foo"})
    Dump.run ["-r", to_string(Repo)]

    repo_msg = "The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been dumped to foo"
    assert_received {:mix_shell, :info, [^repo_msg]}

    migration_repo_msg = "The structure for Mix.Tasks.Ecto.DumpLoadTest.MigrationRepo has been dumped to foo"
    assert_received {:mix_shell, :info, [^migration_repo_msg]}
  end

  test "runs the adapter structure_dump with --quiet" do
    Process.put(:structure_dump, {:ok, "foo"})
    Dump.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "raises an error when structure_dump gives an unknown feedback" do
    Process.put(:structure_dump, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Dump.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on structure_dump when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Structure/, fn ->
      Dump.run ["-r", to_string(NoStructureRepo)]
    end
  end

  ## Load

  test "runs the adapter structure_load" do
    table_exists? = fn _, _ -> false end

    Process.put(:structure_load, {:ok, "foo"})
    Load.run ["-r", to_string(Repo)], table_exists?

    msg = "The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been loaded from foo"
    assert_received {:mix_shell, :info, [^msg]}
  end

  test "runs the adapter structure_load for migration_repo" do
    Application.put_env(:ecto_sql, Repo, [migration_repo: MigrationRepo])

    table_exists? = fn _, _ -> false end

    Process.put(:structure_load, {:ok, "foo"})
    Load.run ["-r", to_string(Repo)], table_exists?

    repo_msg = "The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been loaded from foo"
    assert_received {:mix_shell, :info, [^repo_msg]}

    migration_repo_msg = "The structure for Mix.Tasks.Ecto.DumpLoadTest.MigrationRepo has been loaded from foo"
    assert_received {:mix_shell, :info, [^migration_repo_msg]}
  end

  test "runs the adapter structure_load with --quiet" do
    table_exists? = fn _, _ -> false end
    Process.put(:structure_load, {:ok, "foo"})
    Load.run ["-r", to_string(Repo), "--quiet"], table_exists?
    refute_received {:mix_shell, :info, [_]}
  end

  test "skips when the database is loaded with --skip-if-loaded" do
    table_exists? = fn _, _ -> true end
    assert :ok == Load.run ["-r", to_string(Repo), "--skip-if-loaded"], table_exists?
  end

  test "raises an error when structure_load gives an unknown feedback" do
    table_exists? = fn _, _ -> false end

    Process.put(:structure_load, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Load.run ["-r", to_string(Repo)], table_exists?
    end
  end

  test "raises an error on structure_load when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Structure/, fn ->
      Load.run ["-r", to_string(NoStructureRepo)]
    end
  end
end
