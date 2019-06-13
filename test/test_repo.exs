defmodule EctoSQL.TestAdapter do
  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Transaction
  @behaviour Ecto.Adapter.Migration

  defmacro __before_compile__(_opts), do: :ok
  def ensure_all_started(_, _), do: {:ok, []}

  def init(_opts) do
    child_spec = Supervisor.child_spec {Task, fn -> :timer.sleep(:infinity) end}, []
    {:ok, child_spec, %{meta: :meta}}
  end

  def checkout(_, _, _), do: raise "not implemented"
  def delete(_, _, _, _), do: raise "not implemented"
  def insert_all(_, _, _, _, _, _, _), do: raise "not implemented"
  def rollback(_, _), do: raise "not implemented"
  def stream(_, _, _, _, _), do: raise "not implemented"
  def update(_, _, _, _, _, _), do: raise "not implemented"

  ## Types

  def loaders(_primitive, type), do: [type]
  def dumpers(_primitive, type), do: [type]
  def autogenerate(_), do: nil

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  # Migration emulation

  def execute(_, _, {:nocache, {:all, %{from: %{source: {"schema_migrations", _}}}}}, _, _) do
    {length(migrated_versions()), Enum.map(migrated_versions(), &List.wrap/1)}
  end

  def execute(_, _meta, {:nocache, {:delete_all, %{from: %{source: {"schema_migrations", _}}}}}, [version], _) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end

  def insert(_, %{source: "schema_migrations"}, val, _, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version | migrated_versions()])
    {:ok, []}
  end

  def in_transaction?(_), do: Process.get(:in_transaction?) || false

  def transaction(_mod, _opts, fun) do
    Process.put(:in_transaction?, true)
    send test_process(), {:transaction, fun}
    {:ok, fun.()}
  after
    Process.put(:in_transaction?, false)
  end

  ## Migrations

  def lock_for_migrations(_, query, _opts, fun) do
    send test_process(), {:lock_for_migrations, fun}
    fun.(query)
  end

  def execute_ddl(_, command, _) do
    Process.put(:last_command, command)
    {:ok, []}
  end

  defp migrated_versions do
    Process.get(:migrated_versions, [])
  end

  def supports_ddl_transaction? do
    get_config(:supports_ddl_transaction?, false)
  end

  defp test_process do
    get_config(:test_process, self())
  end

  defp get_config(name, default) do
    :ecto_sql
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(name, default)
  end
end

defmodule EctoSQL.TestRepo do
  use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter
end

EctoSQL.TestRepo.start_link()
EctoSQL.TestRepo.start_link(name: :tenant_db)
