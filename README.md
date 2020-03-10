Ecto SQL
=========
[![Build Status](https://github.com/elixir-ecto/ecto_sql/workflows/CI/badge.svg)](https://github.com/elixir-ecto/ecto_sql/actions)

Ecto SQL ([documentation](https://hexdocs.pm/ecto_sql)) provides building blocks for writing SQL adapters for Ecto. It features:

  * The Ecto.Adapters.SQL module as an entry point for all SQL-based adapters
  * Default implementations for Postgres (Ecto.Adapters.Postgres), MySQL (Ecto.Adapters.MyXQL), and MSSQL (Ecto.Adapters.Tds)
  * A test sandbox (Ecto.Adapters.SQL.Sandbox) that concurrently runs database tests inside transactions
  * Support for database migrations via Mix tasks

To learn more about getting started, [see the Ecto repository](https://github.com/elixir-ecto/ecto). 

## Running tests

Clone the repo and fetch its dependencies:

    $ git clone https://github.com/elixir-ecto/ecto_sql.git
    $ cd ecto_sql
    $ mix deps.get
    $ mix test.all

Note that `mix test.all` runs the tests in `test/` and the `integration_test`s for each adapter: `pg`, `myxql` and `tds`.

You can also use a local Ecto checkout if desired:

    $ ECTO_PATH=../ecto mix test.all

You can run tests against a specific Ecto adapter by using the `ECTO_ADAPTER` environment variable:

    $ ECTO_ADAPTER=pg mix test

MySQL and PostgreSQL can be installed directly on most systems. For MSSQL, you may need to run it as a Docker image:

    docker run -d -p 1433:1433 --name mssql -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=some!Password' mcr.microsoft.com/mssql/server:2017-latest

## License

Copyright (c) 2012 Plataformatec \
Copyright (c) 2020 Dashbit

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
