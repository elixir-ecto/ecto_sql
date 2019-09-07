# Changelog for v3.x

## v3.2.0 (2019-09-07)

This new version requires Elixir v1.6+.

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
