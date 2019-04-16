# Changelog for v3.x

## v3.1.1 (2019-04-16)

### Bug fixes

  * Fix backwards incompatible change in Telemetry metadata

## v3.1.0 (2019-04-02)

v3.1 requires Elixir v1.5+.

### Enhancements

  * Introduce Ecto.Adapters.MyXQL as an alternative library for MySQL
  * Run all migrations in subdirectories
  * Update to Telemetry v0.4.0 (note the measurements value differ from previous versions)

### Bug fixes

  * Respect `:ownership_timeout` repo configuration on SQL Sandbox
  * Commit and relock after every migration to avoid leaving the DB in an inconsistent state under certain failures

## v3.0.5 (2019-02-05)

### Enhancements

  * Add `:repo` and `:type` keys to telemetry events
  * Add `:add_if_not_exists` and `:remove_if_exists` to columns in migrations

### Bug fixes

  * Load all migrations before running them
  * Include `:queue_target` and `:queue_interval` in SQL Sandbox checkout

## v3.0.4 (2018-12-31)

### Enhancements

  * Bump telemetry dependency
  * Perform strict argument parsing in `ecto.migrate`, `ecto.rollback`, `ecto.load` and `ecto.dump`

### Bug fixes

  * Do not log migration versions query

### Deprecations

  * `Telemetry.attach/5` and `Telemetry.attach_many/5` are deprecated in favor of `:telemetry.attach/5` and `:telemetry.attach_many/5`

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
