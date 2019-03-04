Logger.configure(level: :info)

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, false)
Application.put_env(:ecto_sql, :lock_for_update, "FOR UPDATE")

Code.require_file "../support/repo.exs", __DIR__

# Configure MySQL connection
Application.put_env(:ecto_sql, :mysql_test_url,
  "ecto://" <> (System.get_env("MYSQL_URL") || "root@localhost")
)

# Pool repo for async, safe tests
alias Ecto.Integration.TestRepo

Application.put_env(:ecto_sql, TestRepo,
  url: Application.get_env(:ecto_sql, :mysql_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  show_sensitive_data_on_connection_error: true
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.MyXQL

  def create_prefix(prefix) do
    "create database #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop database #{prefix}"
  end

  def uuid do
    Ecto.UUID
  end
end

# Pool repo for non-async tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto_sql, PoolRepo,
  adapter: Ecto.Adapters.MyXQL,
  url: Application.get_env(:ecto_sql, :mysql_test_url) <> "/ecto_test",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true
)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.MyXQL
end

# Load support files
ecto = Mix.Project.deps_paths[:ecto]
Code.require_file "#{ecto}/integration_test/support/schemas.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Ecto.Adapters.MyXQL.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.MyXQL.storage_down(TestRepo.config)
:ok = Ecto.Adapters.MyXQL.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = PoolRepo.start_link()

%{rows: [[version]]} = TestRepo.query!("SELECT @@version", [])

version =
  case Regex.named_captures(~r/(?<major>[0-9]*)(\.(?<minor>[0-9]*))?.*/, version) do
    %{"major" => major, "minor" => minor} -> "#{major}.#{minor}.0"
    %{"major" => major} -> "#{major}.0.0"
    _other -> version
  end

excludes = [
  :array_type,
  :read_after_writes,
  :returning,
  :create_index_if_not_exists,
  :aggregate_filters,
  :transaction_isolation,
  :with_conflict_target,
  :map_boolean_in_expression
]

if Version.match?(version, ">= 8.0.0") do
  ExUnit.configure(exclude: excludes)
else
  ExUnit.configure(exclude: [:rename_column | excludes])
end

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)

ExUnit.start()
