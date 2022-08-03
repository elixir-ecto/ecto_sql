Logger.configure(level: :info)

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, true)
Application.put_env(:ecto_sql, :lock_for_update, "FOR UPDATE")

# Configure PG connection
Application.put_env(:ecto_sql, :pg_test_url,
  "ecto://" <> (System.get_env("PG_URL") || "postgres:postgres@127.0.0.1")
)

Code.require_file "../support/repo.exs", __DIR__

# Pool repo for async, safe tests
alias Ecto.Integration.TestRepo

Application.put_env(:ecto_sql, TestRepo,
  url: Application.get_env(:ecto_sql, :pg_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  show_sensitive_data_on_connection_error: true
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.Postgres

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end

  def uuid do
    Ecto.UUID
  end
end

# Pool repo for non-async tests
alias Ecto.Integration.PoolRepo

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.Postgres
end

# Pool repo for non-async and advisory lock tests
alias Ecto.Integration.AdvisoryLockPoolRepo

defmodule Ecto.Integration.AdvisoryLockPoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.Postgres
end

pool_repo_config = [
  url: Application.get_env(:ecto_sql, :pg_test_url) <> "/ecto_test",
  pool_size: 10,
  max_restarts: 20,
  max_seconds: 10
]

Application.put_env(:ecto_sql, PoolRepo, pool_repo_config)
Application.put_env(:ecto_sql, AdvisoryLockPoolRepo, pool_repo_config ++ [
  migration_source: "advisory_lock_schema_migrations",
  migration_lock: :pg_advisory_lock
])

# Load support files
ecto = Mix.Project.deps_paths()[:ecto]
Code.require_file "#{ecto}/integration_test/support/schemas.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.Postgres.storage_down(TestRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()
{:ok, _pid} = AdvisoryLockPoolRepo.start_link()

%{rows: [[version]]} = TestRepo.query!("SHOW server_version", [])

version =
  case Regex.named_captures(~r/(?<major>[0-9]*)(\.(?<minor>[0-9]*))?.*/, version) do
    %{"major" => major, "minor" => minor} -> "#{major}.#{minor}.0"
    %{"major" => major} -> "#{major}.0.0"
    _other -> version
  end

excludes = [:selected_as_with_having, :selected_as_with_order_by_expression]
excludes_above_9_5 = [:without_conflict_target]
excludes_below_9_6 = [:add_column_if_not_exists, :no_error_on_conditional_column_migration]

if Version.match?(version, "< 9.6.0") do
  ExUnit.configure(exclude: excludes ++ excludes_above_9_5 ++ excludes_below_9_6)
else
  ExUnit.configure(exclude: excludes ++ excludes_above_9_5)
end

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)

ExUnit.start()
