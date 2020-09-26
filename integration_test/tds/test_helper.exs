Logger.configure(level: :info)

ExUnit.start(
  exclude: [
    # not sure how to support this yet
    :aggregate_filters,
    # subquery contains ORDER BY and that is not supported
    :subquery_aggregates,
    # sql don't have array type
    :array_type,
    # I'm not sure if this is even possible if we SET IDENTITY_INSERT ON
    :modify_foreign_key_on_update,
    :modify_foreign_key_on_delete,
    # NEXT 4 exclusions: can only be supported with MERGE statement and it is tricky to make it fast
    :with_conflict_target,
    :without_conflict_target,
    :upsert_all,
    :upsert,
    # I'm not sure why, but if decimal is passed as parameter mssql server will round differently ecto/integration_test/cases/interval.exs:186
    :uses_msec,
    # Unique index compares even NULL values for post_id, so below fails inserting permalinks without setting valid post_id
    :insert_cell_wise_defaults,
    # MSSQL does not support strings on text fields
    :text_type_as_string,
    # IDENTITY_INSERT ON/OFF  must be manually executed
    :assigns_id_type,
    # without schema we don't know anything about :map and :embeds, where value is kept in nvarchar(max) column
    :map_type_schemaless,
    # SELECT NOT(t.bool_fields) is not supported by sql server
    :map_boolean_in_expression,
    # Decimal casting can not be precise in MSSQL adapter since precision is kept in migration file :(
    # or in case of schema-less queries we don't know at all about precision
    :decimal_precision,
    # this fails because schema-less queries in select uses Decimal casting,
    # see below comment about :decimal_type_cast exclusion or :decimal_type_cast
    :union_with_literals,
    # inline queries can't use order by
    :inline_order_by,
    # running destruction of PK columns requires that PK constraint is dropped first
    :alter_primary_key,
    # below 2 exclusions (in theory) requires filtered unique index on permalinks table post_id column e.g.
    #   CREATE UNIQUE NONCLUSTERED INDEX idx_tbl_TestUnique_ID
    #   ON [permalinks] ([post_id])
    #   WHERE [post_id] IS NOT NULL
    # But I couldn't make it work :(
    :on_replace_nilify,
    :on_replace_update,
    # This can't be executed since it requires
    # `SET IDENTITY_INSERT [ [ database_name . ] schema_name . ] table_name  ON`
    # and after insert we need to turn it on, must be run manually in transaction
    :pk_insert,
    # Tds allows nested transactions so this will never raise and SQL query should be "BEGIN TRAN"
    :transaction_checkout_raises,
    # JSON_VALUE always returns strings (even for e.g. integers) and returns null for
    # arrays/objects (JSON_QUERY must be used for these)
    :json_extract_path
  ]
)

Application.put_env(:tds, :json_library, Jason)
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, false)
Application.put_env(:ecto_sql, :lock_for_update, "(UPDLOCK)")

Application.put_env(
  :ecto_sql,
  :tds_test_url,
  "ecto://" <> (System.get_env("MSSQL_URL") || "sa:some!Password@localhost")
)

alias Ecto.Integration.TestRepo

# Load support files
ecto = Mix.Project.deps_paths()[:ecto]
Code.require_file("../support/repo.exs", __DIR__)

Application.put_env(
  :ecto_sql,
  TestRepo,
  url: Application.get_env(:ecto_sql, :tds_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  set_allow_snapshot_isolation: :on,
  show_sensitive_data_on_connection_error: true
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto_sql,
    adapter: Ecto.Adapters.Tds

  def uuid, do: Tds.Ecto.UUID

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

alias Ecto.Integration.PoolRepo

Application.put_env(
  :ecto_sql,
  PoolRepo,
  url: "#{Application.get_env(:ecto_sql, :tds_test_url)}/ecto_test",
  pool_size: 10,
  set_allow_snapshot_isolation: :on
)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo,
    otp_app: :ecto_sql,
    adapter: Ecto.Adapters.Tds

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup context do
    level = Map.get(context, :isolation_level, :read_committed)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo, isolation_level: level)
  end
end

# :dbg.start()
# :dbg.tracer()
# :dbg.p(:all,:c)
# :dbg.tpl(Ecto.Adapters.Tds.Connection, :column_change, :x)
# :dbg.tpl(Ecto.Adapters.Tds.Connection, :execute_ddl, :x)
# :dbg.tpl(Ecto.Adapters.Tds.Connection, :all, :x)
# :dbg.tpl(Tds.Parameter, :prepare_params, :x)
# :dbg.tpl(Tds.Parameter, :prepared_params, :x)

{:ok, _} = Ecto.Adapters.Tds.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_ = Ecto.Adapters.Tds.storage_down(TestRepo.config())
:ok = Ecto.Adapters.Tds.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()
:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: :debug)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
