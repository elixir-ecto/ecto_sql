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
    $ mix test

In case you are modifying Ecto and EctoSQL at the same time, you can configure EctoSQL to use an Ecto version from your machine by running:

    $ ECTO_PATH=../ecto mix test.all

### Running integration tests

The command above will run unit tests. EctoSQL also has a suite of integration tests for its built-in adapters: `pg`, `myxql` and `tds`. If you are changing logic specific to a database, we recommend running its respective integration test suite as well. Doing so requires you to have the database available locally. MySQL and PostgreSQL can be installed directly on most systems. For MSSQL, you may need to run it as a Docker image:

    docker run -d -p 1433:1433 --name mssql -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=some!Password' mcr.microsoft.com/mssql/server:2017-latest

Once the database is running, you can run tests against a specific Ecto adapter by using the `ECTO_ADAPTER` environment variable:

    $ ECTO_ADAPTER=pg mix test

You may also run `mix test.all` to run the unit tests and all integration tests. You can also use a local Ecto checkout if desired:

    $ ECTO_PATH=../ecto mix test.all

### Running databases with Docker

You can also run all databases with Docker:

    $ docker run --name pg -d -p 5432:5432 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres postgres:16.2-alpine
    $ docker run --name mysql -d -p 3306:3306 -e MYSQL_ROOT_PASSWORD=root mysql:8.0 --sql_mode="ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ANSI_QUOTES" --default-authentication-plugin=mysql_native_password
    $ docker run --name mssql -d -p 1433:1433 -e ACCEPT_EULA=Y -e 'MSSQL_SA_PASSWORD=some!Password' mcr.microsoft.com/mssql/server:2022-latest

And then point the tests to them:

    $ PG_URL=postgres:postgres@127.0.0.1 MYSQL_URL=root:root@127.0.0.1 MSSQL_URL='sa:some!Password@127.0.0.1' mix test.all

The `pg` and `myxql` integration tests also require the `pg_dump`/`psql` and `mysqldump`/`mysql` clients, respectively.

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
