# Changelog for v3.x

## v3.5.1 (2020-10-12)

### Enhancements

  * [tds] Support explain plan for the TDS adapter

### Bug fix

  * [migrations] Reload all migrations once the lock is free to avoid running the same migration more than once
  * [query] Support nested subqueries

## v3.5.0 (2020-10-03)

### Enhancements

  * [migrations] Add option to skip schema migrations table checks
  * [migrations] Add `:migration_repo` configuration to allow a different repository to host the schema migrations
  * [migrations] Support `validate: false` on references and constraints
  * [migrations] Accept `:migration_primary_key` as false and add `:migration_foreign_key` repo config
  * [postgres] Support for `:identity` key types in Postgres 10 or later
  * [postgres] Use IF NOT EXIST when creating index with `create_if_not_exists`, this requires PG 9.5+ or later
  * [repo] Support `Repo.explain(:all | :update_all | :delete_all, query)` for Ecto adapters
  * [sandbox] Allow for dynamic repos to be checked out in sandbox

### Bug fixes

  * [migrations] Flush migration commands before executing `before_commit` callback
  * [migrations] Do not swallow errors when migration lock is disabled

## v3.4.5 (2020-07-05)

### Bug fixes

  * [ecto] Fix warnings on Elixir v1.11
  * [migrations] Migration prefix should have higher preference than `default_options`

## v3.4.4 (2020-05-19)

### Enhancements

  * [sandbox] Add `Ecto.Adapters.SQL.start_owner!/2` and `Ecto.Adapters.SQL.stop_owner/1`
  * [myxql] Decode BIT columns when using MyXQL and `:boolean` type
  * [migrations] Use one line per migration in the schema dump

## v3.4.3 (2020-04-27)

### Bug fixes

  * [ecto] Support `as` and `parent_as` from Ecto v3.4.3+
  * [ecto] Support `x in subquery(query)` from Ecto v3.4.3+

## v3.4.2 (2020-04-02)

### Bug fixes

  * [myxql] A binary with size should be a varbinary
  * [mssql] A binary without size should be a varbinary(max)

## v3.4.1 (2020-03-25)

### Bug fixes

  * [myxql] Assume the reference does not change in MyXQL and prepare for v0.4.0

## v3.4.0 (2020-03-24)

### Enhancements

  * [adapters] Support Ecto's v3.4 `json_extract_path/2`
  * [migrations] Support multiple migration paths to be given with `--migration-path`
  * [mssql] Add built-in support to MSSQL via the TDS adapter
  * [repo] Support custom options on telemetry

## v3.3.4 (2020-02-14)

### Enhancements

  * [adapters] Support fragments in locks
  * [migration] Add `:include` option to support covering indexes

## v3.3.3 (2020-01-28)

### Enhancements

  * [myxql] Allow not setting the encoding when creating a database

### Bug fixes

  * [myxql] Removing prefixed table name from constraints on latest MySQL versions
  * [sql] Fix precedence of `is_nil` when inside a comparison operator

## v3.3.2 (2019-12-15)

### Bug fixes

  * [adapters] Start StorageSupervisor before using it

## v3.3.1 (2019-12-15)

### Bug fixes

  * [adapters] Do not leak PIDs on storage commands
  * [migrations] Use :migration_primary_key in create/1

## v3.3.0 (2019-12-11)

### Enhancements

  * [ecto] Upgrade and support Ecto v3.3
  * [repo] Include `:idle_time` on telemetry measuremnts
  * [migration] Support anonymous functions in `Ecto.Migration.execute/2`

### Bug fixes

  * [migration] Ensure that flush() will raise on rollback if called from `change/0`

## v3.2.2 (2019-11-25)

### Enhancements

  * [mysql] Support myxql v0.3

## v3.2.1 (2019-11-02)

### Enhancements

  * [migration] Support anonymous functions in execute

### Bug fixes

  * [mix ecto.create] Change default charset in MyXQL to utf8mb4

## v3.2.0 (2019-09-07)

This new version requires Elixir v1.6+. Note also the previously soft-deprecated `Ecto.Adapters.MySQL` has been removed in favor of `Ecto.Adapters.MyXQL`. We announced the intent to remove `Ecto.Adapters.MySQL` back in v3.0 and `Ecto.Adapters.MyXQL` has been tested since then and ready for prime time since v3.1.

### Enhancements

  * [sql] Use `get_dynamic_repo` on SQL-specific functions
  * [sql] Respect `Ecto.Type.embed_as/2` choice when loading/dumping embeds (Ecto 3.2+ compat)
  * [sql] Support CTE expressions (Ecto 3.2+ compat)

### Bug fixes

  * [sql] Fix generated "COMMENT ON INDEX" for PostgreSQL

## v3.1.6 (2019-06-27)

### Enhancements

  * [sql] Set `cache_statement` for `insert_all`

## v3.1.5 (2019-06-13)

### Enhancements

  * [migration] Add `@disable_migration_lock` to be better handle concurrent indexes
  * [mysql] Set `cache_statement` for inserts

### Deprecations

  * [mysql] Deprecate Ecto.Adapters.MySQL

## v3.1.4 (2019-05-28)

### Enhancements

  * [migrator] Print warning message if concurrent indexes are used with migration lock

## v3.1.3 (2019-05-19)

### Enhancements

  * [migrator] Add `--migrations-path` to ecto.migrate/ecto.rollback/ecto.migrations Mix tasks

### Bug fixes

  * [migrator] Make sure an unboxed run is performed when running migrations with the ownership pool

## v3.1.2 (2019-05-11)

### Enhancements

  * [migrator] Add `Ecto.Migrator.with_repo/2` to start repo and apps
  * [mix] Add `--skip-if-loaded` for `ecto.load`
  * [sql] Add `Ecto.Adapters.SQL.table_exists?/2`

## v3.1.1 (2019-04-16)

### Bug fixes

  * [repo] Fix backwards incompatible change in Telemetry metadata

## v3.1.0 (2019-04-02)

v3.1 requires Elixir v1.5+.

### Enhancements

  * [mysql] Introduce Ecto.Adapters.MyXQL as an alternative library for MySQL
  * [migrations] Run all migrations in subdirectories
  * [repo] Update to Telemetry v0.4.0 (note the measurements value differ from previous versions)

### Bug fixes

  * [sandbox] Respect `:ownership_timeout` repo configuration on SQL Sandbox
  * [migrations] Commit and relock after every migration to avoid leaving the DB in an inconsistent state under certain failures

### Backwards incompatible changess

  * [migrations] If you are creating indexes concurrently, you need to disable the migration lock: `config :app, App.Repo, migration_lock: nil`. This will migrations behave the same way as they did in Ecto 2.0.

## v3.0.5 (2019-02-05)

### Enhancements

  * [repo] Add `:repo` and `:type` keys to telemetry events
  * [migrations] Add `:add_if_not_exists` and `:remove_if_exists` to columns in migrations

### Bug fixes

  * [migrations] Load all migrations before running them
  * [sandbox] Include `:queue_target` and `:queue_interval` in SQL Sandbox checkout

## v3.0.4 (2018-12-31)

### Enhancements

  * [repo] Bump telemetry dependency
  * [migrations] Perform strict argument parsing in `ecto.migrate`, `ecto.rollback`, `ecto.load` and `ecto.dump`

### Bug fixes

  * [migrations] Do not log migration versions query

### Deprecations

  * [repo] `Telemetry.attach/5` and `Telemetry.attach_many/5` are deprecated in favor of `:telemetry.attach/5` and `:telemetry.attach_many/5`

## v3.0.3 (2018-11-29)

### Enhancements

  * [migration] Support `after_begin` and `before_commit` migration callbacks
  * [migration] Add `:prefix` option to `references/2`

### Bug fixes

  * [migration] Do not start a transaction for migrated versions if there is no `:migration_lock`
  * [migration] Fix removing an reference column inside alter table
  * [migration] Warn on removed `:pool_timeout` option

## v3.0.2 (2018-11-20)

### Enhancements

  * [query] Support `Ecto.Query` in `insert_all` values
  * [migration] Add `Ecto.Migration.repo/0`

## v3.0.1 (2018-11-17)

### Enhancements

  * [migrations] Support `drop_if_exists` for constraints

### Bug fixes

  * [migrations] Only commit migration transaction if migration can be inserted into the DB
  * [migrations] Do not run migrations from `_build` when using Mix
  * [migrations] Improve errors when checking in already committed sandboxes
  * [mysql] Do not pass nil for `--user` to mysqldump
  * [package] Require Ecto 3.0.2 with bug fixes
  * [package] Require Mariaex 0.9.1 which fixes a bug when used with Ecto 3.0.2
  * [sandbox] Raise when using sandbox on non-sandbox pools

## v3.0.0 (2018-10-29)

  * Initial release
