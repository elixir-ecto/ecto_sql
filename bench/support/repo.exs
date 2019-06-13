pg_bench_url = System.get_env("PG_URL") || "postgres:postgres@localhost"
myxql_bench_url = System.get_env("MYXQL_URL") || "root@localhost"

Application.put_env(
  :ecto_sql,
  Ecto.Bench.PgRepo,
  url: "ecto://" <> pg_bench_url <> "/ecto_test",
  adapter: Ecto.Adapters.Postgres,
  show_sensitive_data_on_connection_error: true
)

Application.put_env(
  :ecto_sql,
  Ecto.Bench.MyXQLRepo,
  url: "ecto://" <> myxql_bench_url <> "/ecto_test_myxql",
  adapter: Ecto.Adapters.MyXQL,
  protocol: :tcp,
  show_sensitive_data_on_connection_error: true
)

defmodule Ecto.Bench.PgRepo do
  use Ecto.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.Postgres, log: false
end

defmodule Ecto.Bench.MyXQLRepo do
  use Ecto.Repo, otp_app: :ecto_sql, adapter: Ecto.Adapters.MyXQL, log: false
end
