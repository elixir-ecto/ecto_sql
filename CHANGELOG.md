# Changelog for v3.0

## v3.0.1 (2018-11-17)

## Enhancements

  * [migrations] Support `drop_if_exists` for constraints

## Bug fixes

  * [migrations] Only commit migration transaction if migration can be inserted into the DB
  * [migrations] Do not run migrations from `_build` when using Mix
  * [migrations] Improve errors when checking in already committed sandboxes
  * [mysql] Do not pass nil for `--user` to mysqldump
  * [package] Require Ecto 3.0.2 with bug fixes
  * [package] Require Mariaex 0.9.1 which fixes a bug when used with Ecto 3.0.2
  * [sandbox] Raise when using sandbox on non-sandbox pools

## v3.0.0 (2018-10-29)

  * Initial release. Note support for `mariaex` will be deprecated in a future patch release in favor of the upcoming `myxql` driver, which is being finalized.
