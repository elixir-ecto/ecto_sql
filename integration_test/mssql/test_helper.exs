Logger.configure(level: :info)

ExUnit.start(
  exclude: [
    :aggregate_filters,
    :subquery_aggregates,
    :array_type,
    :modify_foreign_key_on_update,
    :modify_foreign_key_on_delete,
    :with_conflict_target,
    :without_conflict_target,
    :upsert_all,
    :upsert,
    :uses_msec,
    :insert_cell_wise_defaults,
    :select_not,
    :coalesce_type,
    :assigns_id_type,
    :map_type_schemaless,
    :map_boolean_in_expression,
    :text_compare,
    :decimal_type_cast,
    :union_with_literals,
    :db_engine_can_maintain_precision,
    :inline_order_by,
    :uses_usec,
    # running destruction of PK columns requires that constraint is dropped first
    :alter_primary_key,
    :modify_column_with_from,
    :on_replace_nulify,
    :on_replace_update,
    :unique_constraint_conflict,
    :pk_insert,
    :transaction_checkout_raises,
    :transaction_multi_repo_calls,
    # requires transaction isolation level to be set to ON and transaction isolation to :snapshot
    :transaction_not_shared
  ]
)

Application.put_env(:tds, :json_library, Jason)
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, false)
Application.put_env(:ecto_sql, :lock_for_update, "(UPDLOCK)")

Application.put_env(
  :ecto_sql,
  :mssql_test_url,
  "ecto://" <> (System.get_env("MSSQL_URL") || "sa:some!Password@localhost")
)

alias Ecto.Integration.TestRepo

# Load support files
ecto = Mix.Project.deps_paths()[:ecto]
Code.require_file("../support/repo.exs", __DIR__)

Application.put_env(
  :ecto_sql,
  TestRepo,
  url: Application.get_env(:ecto_sql, :mssql_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto_sql,
    adapter: Ecto.Adapters.MsSql

  def uuid, do: Tds.Types.UUID

  def create_prefix(prefix) do
    """
    CREATE SCHEMA #{prefix};
    """
  end

  def drop_prefix(prefix) do
    """
    DROP SCHEMA #{prefix};
    """
  end
end

Code.require_file("#{ecto}/integration_test/support/schemas.exs", __DIR__)
Code.require_file("../support/migration.exs", __DIR__)
Code.require_file("migration.exs", __DIR__)

alias Ecto.Integration.PoolRepo

Application.put_env(
  :ecto_sql,
  PoolRepo,
  url: "#{Application.get_env(:ecto_sql, :mssql_test_url)}/ecto_test"
)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto_sql,
    adapter: Ecto.Adapters.MsSql

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Ecto.Adapters.MsSql.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_ = Ecto.Adapters.MsSql.storage_down(TestRepo.config())
:ok = Ecto.Adapters.MsSql.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()
:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: :debug)
:ok = Ecto.Migrator.up(TestRepo, 1, Ecto.Integration.Migration2, log: :debug)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
