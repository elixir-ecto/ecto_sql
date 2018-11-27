Logger.configure(level: :info)

ExUnit.start exclude: [:assigns_id_type, :array_type, :case_sensitive,
                       :modify_foreign_key_on_update, :modify_foreign_key_on_delete,
                       :uses_usec, :lock_for_update, :with_conflict_target,
                       :with_conflict_ignore]

Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, false)
Application.put_env(:ecto_sql, :lock_for_update, "FOR UPDATE")

# Load support files
ecto = Mix.Project.deps_paths[:ecto]
Code.require_file "#{ecto}/integration_test/support/schemas.exs", __DIR__
Code.require_file "../support/repo.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

alias Ecto.Integration.TestRepo

Application.put_env(
  :ecto_sql,
  TestRepo,
  hostname: System.get_env("SQL_HOSTNAME") || "localhost",
  username: System.get_env("SQL_USERNAME") || "sa",
  password: System.get_env("SQL_PASSWORD") || "some!Password",
  database: "ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  set_allow_snapshot_isolation: :on,
  filter_null_on_unique_indexes: true
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.MsSql
end

alias Ecto.Integration.PoolRepo

Application.put_env(
  :ecto_sql,
  PoolRepo,
  adapter: Ecto.Adapters.MsSql,
  hostname: System.get_env("SQL_HOSTNAME") || "localhost",
  username: System.get_env("SQL_USERNAME") || "sa",
  password: System.get_env("SQL_PASSWORD") || "some!Password",
  database: "ecto_test",
  set_allow_snapshot_isolation: :on
)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.MsSql

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
_   = Ecto.Adapters.MsSql.storage_down(TestRepo.config)
:ok = Ecto.Adapters.MsSql.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link
:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
