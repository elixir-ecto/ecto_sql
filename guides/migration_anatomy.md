# Anatomy of a Migration

[Ecto migrations](`Ecto.Migration`) are used to do the following:

* Change the structure of the database, such as adding fields, tables, or indexes to improve lookups (DDL).
* Populating fields with modified data or new data (DML).

In order for us to create and run safe Ecto migrations on our database, it is helpful to understand what is actually happening with the database. To do that, we'll dig deeper into how Ecto migrations work by looking both at the code being executed and the Postgres logs.

To generate a migration, we'll use run a mix task:

```bash
mix ecto.gen.migration create_weather_table
```

> #### Tip {: .tip}
>
> If you're using Phoenix, you might consider `mix phx.gen.schema` which will generate a migration and also allows you to pass in fields and types. See `mix help phx.gen.schema` for more information.

This command will generate a file in `priv/repo/migrations` given the repo name of `Repo`. If you named it `OtherRepo` the file would be `in priv/other_repo/migrations`.

Let's look at that file:

```elixir
defmodule MyApp.Repo.Migrations.CreateWeatherTable do
  use Ecto.Migration

  def change do

  end
end
```

Let's make some changes; how about we create a table that tracks a city's climate?

```elixir
defmodule MyApp.Repo.Migrations.CreateWeatherTable do
  use Ecto.Migration

  def change do
    create table("weather") do
      add :city,    :string, size: 40
      add :temp_lo, :integer
      add :temp_hi, :integer
      add :prcp,    :float

      timestamps()
    end
  end
end
```

Now that we have a migration, let's run it! Run `mix ecto.migrate`:

```shell
$ mix ecto.migrate
21:26:18.992 [info]  == Running 20210702012346 MyApp.Repo.Migrations.CreateWeatherTable.change/0 forward
21:26:18.994 [info]  create table weather
21:26:19.004 [info]  == Migrated 20210702012346 in 0.0s
```

## Inspect SQL

Understanding exactly what SQL commands are running is helpful to ensure safe migrations, so how do we see the SQL that is executed? By default, Ecto does not log the raw SQL. First, I'll rollback, and then re-migrate but with an additional flag `--log-migrations-sql` so we can see what actually runs.

```shell
$ mix ecto.rollback
== Running 20210702012346 MyApp.Repo.Migrations.CreateWeatherTable.change/0 backward
drop table weather
== Migrated 20210702012346 in 0.0s
```

```shell
$ mix ecto.migrate --log-migrations-sql
== Running 20210702012346 MyApp.Repo.Migrations.CreateWeatherTable.change/0 forward
create table weather
QUERY OK db=3.2ms
CREATE TABLE "weather" ("id" bigserial, "city" varchar(40), "temp_lo" integer, "temp_hi" integer, "prcp" float, "inserted_at" timestamp(0) NOT NULL, "updated_at" timestamp(0) NOT NULL, PRIMARY KEY ("id")) []
21:29:36.467 [info]  == Migrated 20210702012346 in 0.0s
```

Ecto logged the SQL for our changes, but we're not seeing all the SQL that Ecto is running for the migration-- we're missing the Ecto.Migrator SQL that manages the migration. To get these missing logs, we'll also use another flag, `--log-migrator-sql`. Here I am tailing the PostgreSQL server logs:

```shell
$ mix ecto.rollback
$ mix ecto.migrate --log-migrator-sql --log-migrations-sql
```

```
begin []
LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE []
begin []
== Running 20210702012346 MyApp.Repo.Migrations.CreateWeatherTable.change/0 forward
create table weather
QUERY OK db=14.8ms
CREATE TABLE "weather" ("id" bigserial, "city" varchar(40), "temp_lo" integer, "temp_hi" integer, "prcp" float, "inserted_
at" timestamp(0) NOT NULL, "updated_at" timestamp(0) NOT NULL, PRIMARY KEY ("id")) []
== Migrated 20210702012346 in 0.0s
QUERY OK source="schema_migrations" db=5.1ms
INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2) [20210718204657, ~N[2021-07-18 18:20:46]]
QUERY OK db=1.0ms
commit []
QUERY OK db=0.3ms
commit []
```

Inside the transaction, the Ecto Postgres adapter obtains a `SHARE UPDATE EXCLUSIVE` lock of the "schema_migrations" table.

**Why this lock is important**: Systems at scale may have multiple instances of the application connected to the same database, and during a deployment all of the instances rolling out may try to migrate that database at the same time, Ecto leverages this `SHARE UPDATE EXCLUSIVE` lock as a way to ensure that only one instance is running a migration at a time and only once.

This is what the migration actually looks like:

```sql
BEGIN;
LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE;
BEGIN;
CREATE TABLE "weather" ("id" bigserial, "city" varchar(40), "temp_lo" integer, "temp_hi" integer, "prcp" float, "inserted_at" timestamp(0) NOT NULL, "updated_at" timestamp(0) NOT NULL, PRIMARY KEY ("id"));
INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ('20210718204657','2021-07-18 20:53:49');
COMMIT;
COMMIT;
```

When a migration fails, the transaction is rolled back and no changes are kept in the database. In most situations, these are great defaults.

Veteran database administrators may notice the database transactions (`BEGIN`/`COMMIT`) and wonder how to turn those off in situations where transactions could cause problems; such as when adding indexes concurrently; Ecto provides some options that can help with transactions and locks.  Let's explore some of those options next.

## Migration Options

A typical migration has this structure (reminder: this guide is using Postgres; other adapters will vary):

```sql
BEGIN;
  LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE;
  BEGIN;
    -- after_begin callback
    -- my_changes
    -- before_commit callback
    INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
  COMMIT;
COMMIT;
```

_`my_changes` refers to the changes you specify in each of your migrations._

### `@disable_migration_lock`

By default, Ecto acquires a lock on the "schema_migrations" table during the migration transaction:

```sql
BEGIN;
  -- THIS LOCK
  LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE
  BEGIN;
    -- after_begin callback
    -- my_changes
    -- before_commit callback
    INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
  COMMIT;
COMMIT;
```

You want this lock for most migrations because running multiple migrations simultaneously without this lock could have unpredictable results. In database transactions, any locks obtained inside the transaction are released when the transaction is committed, which then unblocks other transactions that touch the same records to proceed.

However, there are some scenarios where you don't want a lock. We'll explore these scenarios later on (for example, backfilling data and creating indexes).

You can skip this lock in Ecto by setting the module attribute `@disable_migration_lock true` in your migration. When the migration lock is disabled, the migration looks like this:

```sql
BEGIN;
  -- after_begin callback
  -- my changes
  -- before_commit callback
  INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
COMMIT;
```

### `@disable_ddl_transaction`

By default, Ecto wraps your changes in a transaction:

```sql
BEGIN;
  LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE
  -- THIS TRANSACTION
  BEGIN;
    -- after_begin callback
    -- my changes
    -- before_commit callback
    INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
  COMMIT;
  -- THIS TRANSACTION
COMMIT;
```

This ensures that when failures occur during a migration, your database is not left in an incomplete or mangled state.

There are scenarios where you don't want a migration to run inside a transaction. Like when performing data migrations or when running commands such as `CREATE INDEX CONCURRENTLY` that can run in the background in the database after you issue the command and cannot be inside a transaction.

You can disable this transaction by setting the module attribute `@disable_ddl_transaction true` in your migration. The migration then looks like this:

```sql
BEGIN;
  LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE
  -- my_changes
  INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
COMMIT;
```

> #### Tip {: .tip}
>
> For Postgres, when disabling transactions, you'll also want to disable the migration lock since that uses yet another transaction. When running these migrations in a multi-node environment, you'll need a process to ensure these migrations are only run once since there is no protection against multiple nodes running the same migration at the same exact time.

Disabling both the migration lock and the DDL transaction, your migration will be pretty simple:

```sql
-- my_changes
INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
```

### Transaction Callbacks

In the examples above, you'll notice there are `after_begin` and `before_commit` hooks if the migration is occurring within a transaction:

```sql
BEGIN;
  -- after_begin hook
  -- my_changes
  -- before_commit hook
  INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ($1,$2);
COMMIT;
```

You can use these hooks by defining `after_begin/0` and `before_commit/0` in your migration. A good use case for this is setting migration lock timeouts as safeguards (see later Safeguards section).

```elixir
defmodule MyApp.Repo.Migrations.CreateWeatherTable do
  use Ecto.Migration

  def change do
    # ... my potentially long-locking migration
  end

  def after_begin do
    execute "SET lock_timeout TO '5s'", "SET lock_timeout TO '10s'"
  end
end
```

> #### Caution {: .warning}
>
> Be aware that these callbacks are not called when `@disable_ddl_transaction true` is configured because they rely on the transaction being present.

## Inspecting Locks In a Query

Before we dive into safer migration practices, we should cover how to check if a migration could potentially block your application. In Postgres, there is a `pg_locks` table that we can query that reveals the locks in the system. Let's query that table alongside our changes from the migration, but return the locks so we can see what locks were obtained from the changes.

```sql
BEGIN;
  -- Put your actions in here. For example, validating a constraint
  ALTER TABLE addresses VALIDATE CONSTRAINT "my_table_locking_constraint";

  -- end your transaction with a SELECT on pg_locks so you can see the locks
  -- that occurred during the transaction
  SELECT locktype, relation::regclass, mode, transactionid AS tid, virtualtransaction AS vtid, pid, granted FROM pg_locks;
COMMIT;
```

The result from this SQL command should return the locks obtained during the database transaction. Let's see an example: We'll add a unique index without concurrency so we can see the locks it obtains:

```sql
BEGIN;
  LOCK TABLE "schema_migrations" IN SHARE UPDATE EXCLUSIVE MODE;
  -- we are going to squash the embedded transaction here for simplicity
  CREATE UNIQUE INDEX IF NOT EXISTS "weather_city_index" ON "weather" ("city");
  INSERT INTO "schema_migrations" ("version","inserted_at") VALUES ('20210718210952',NOW());
  SELECT locktype, relation::regclass, mode, transactionid AS tid, virtualtransaction AS vtid, pid, granted FROM pg_locks;
COMMIT;

--    locktype    |      relation      |           mode           |  tid   | vtid  | pid | granted
-- ---------------+--------------------+--------------------------+--------+-------+-----+---------
--  relation      | pg_locks           | AccessShareLock          |        | 2/321 | 253 | t
--  relation      | schema_migrations  | RowExclusiveLock         |        | 2/321 | 253 | t
--  virtualxid    |                    | ExclusiveLock            |        | 2/321 | 253 | t
--  relation      | weather_city_index | AccessExclusiveLock      |        | 2/321 | 253 | t
--  relation      | schema_migrations  | ShareUpdateExclusiveLock |        | 2/321 | 253 | t
--  transactionid |                    | ExclusiveLock            | 283863 | 2/321 | 253 | t
--  relation      | weather            | ShareLock                |        | 2/321 | 253 | t
-- (7 rows)
```

Let's go through each of these:

1. `relation | pg_locks | AccessShareLock` - This is us querying the `"pg_locks"` table in the transaction so we can see which locks are taken. It has the weakest lock which only conflicts with `AccessExclusive` which should never happen on the internal `"pg_locks"` table itself.
1. `relation | schema_migrations | RowExclusiveLock` - This is because we're inserting a row into the `"schema_migrations"` table. Reads are still allowed, but mutation on this table is blocked until the transaction is done.
1. `virtualxid | _ | ExlusiveLock` - Querying `pg_locks` created a virtual transaction on the `SELECT` query. We can ignore this.
1. `relation | weather_city_index | AccessExclusiveLock` - We're creating the index, so this new index will be completely locked to any reads and writes until this transaction is complete.
1. `relation | schema_migrations | ShareUpdateExclusiveLock` - This lock is acquired by Ecto to ensure that only one mutable operation is happening on the table. This is what allows multiple nodes able to run migrations at the same time safely. Other processes can still read the `"schema_migrations"` table, but you cannot write to it.
1. `transactionid | _ | ExclusiveLock` - This lock is on a transaction that is happening; in this case, it has an `ExclusiveLock` on itself; meaning that if another transaction occurring at the same time conflicts with this transaction, the other transaction will acquire a lock on this transaction so it knows when it's done. I call this "lockception".
1. `relation | weather | ShareLock` - Finally, the reason why we're here. Remember, we're creating a unique index on the `"weather"` table without concurrency. This lock is our red flag. Notice it acquires a ShareLock on the table. This means it blocks writes! That's not good if we deploy this and have processes or web requests that regularly write to this table. `UPDATE`, `DELETE`, and `INSERT` acquire a `RowExclusiveLock` which conflicts with the ShareLock.

To avoid this lock, we change the command to `CREATE INDEX CONCURRENTLY ...`; when using `CONCURRENTLY`, it prevents us from using database transactions which is unfortunate because now we cannot easily see the locks the command obtains. We know this will be safer however because `CREATE INDEX CONCURRENTLY` acquires a `ShareUpdateExclusiveLock` which does not conflict with `RowExclusiveLock` (See Reference Material in the [Safe Migrations guide](safe_migrations.html)).

This scenario is revisited later in [Safe Migrations](safe_migrations.html).

## Safeguards in the database

It's a good idea to add safeguards so no developer on the team accidentally locks up the database for too long. Even if you know all about databases and locks, you might have a forgetful day and try to add an index non-concurrently and bring down production. Safeguards are good.

We can add one or more safeguards:

1. Automatically cancel a statement if the lock is held for too long. There are two ways to do this:
  1. Apply to migrations. This can be done with a lock_timeout inside a transaction.
  2. Apply to any statements. This can be done by setting a lock_timeout on a Postgres role.
2. Automatically cancel statements that take too long. This is broader than #1 because it includes any statement, not just locks.

Let's dive into these safeguards.

### Add a `lock_timeout`

One safeguard we can add to migrations is a lock timeout. A lock timeout ensures a lock will not last more than n seconds. This way, when an unsafe migration sneaks in, it only locks tables to updates and writes (and possibly reads) for n seconds instead of indefinitely when the migration finishes.

From the Postgres docs:

> Abort any statement that waits longer than the specified amount of time while attempting to acquire a lock on a table, index, row, or other database object. The time limit applies separately to each lock acquisition attempt. The limit applies both to explicit locking requests (such as LOCK TABLE, or SELECT FOR UPDATE without NOWAIT) and to implicitly-acquired locks. If this value is specified without units, it is taken as milliseconds. A value of zero (the default) disables the timeout.
>
> Unlike `statement_timeout`, this timeout can only occur while waiting for locks. Note that if `statement_timeout` is nonzero, it is rather pointless to set lock_timeout to the same or larger value, since the statement timeout would always trigger first. If `log_min_error_statement` is set to `ERROR` or lower, the statement that timed out will be logged.

There are two ways to apply this lock:

1. localized to the transaction
2. default for the user/role

Let's go through those options:

####  Transaction lock_timeout

In SQL:

```sql
SET LOCAL lock_timeout TO '5s';
```

Let's move that to an Ecto migration transaction callback. Since this `lock_timeout` will be in a database transaction for Postgres, we will use `SET LOCAL lock_timeout` so that the `lock_timeout` only alters this database transaction and not the session.

You can set a lock timeout in every migration:

```elixir
def after_begin do
  # execute/2 can be ran in both migration directions, up/down.
  # The first argument will be ran when migrating up.
  # The second argument will be ran when migrating down. You might give yourself
  # a couple extra seconds when rolling back.
  execute("SET LOCAL lock_timeout TO '5s'", "SET LOCAL lock_timeout TO '10s'")
end
```

But this can get tedious since you'll likely want this for every migration. Let's write a little macro to help with this boilerplate code.

In every migration, you'll notice that we `use Ecto.Migration` which inserts some code into your migration. Let's use this same idea to inject a boilerplate of our own and leverage an option to set a lock timeout. We define the `after_begin/0` callback to set the lock timeout.

```elixir
defmodule MyApp.Migration do
  defmacro __using__(opts) do
    lock_timeout = Keyword.get(opts, :lock_timeout, [up: "5s", down: "10s"])

    quote do
      use Ecto.Migration

      if unquote(lock_timeout) do
        def after_begin do
          execute(
            "SET LOCAL lock_timeout TO '#{Keyword.fetch!(unquote(lock_timeout), :up)}'",
            "SET LOCAL lock_timeout TO '#{Keyword.fetch!(unquote(lock_timeout), :down)}'"
          )
        end
      end
    end
  end
end
```

And adjust our migration:

```diff
defmodule MyApp.Repo.Migrations.CreateWeatherTable do
-  use Ecto.Migration
+  use MyApp.Migration

  def change do
    # my changes
  end
end
```

Now the migrations will only be allowed to acquire locks up to 5 seconds when migrating up and 10 seconds when rolling back. Remember, these callbacks are not called when `@disable_ddl_transaction true` is set.

You can override the lock timeout if needed by passing in options:

```elixir
# disable the lock_timeout
use MyApp.Migration, lock_timeout: false

# or change the timeouts
use MyApp.Migration, lock_timeout: [up: "10s", down: "20s"]
```

Let's now make Ecto use our custom Migration module by default when generating new migrations:

```elixir
# config/config.exs
config :ecto_sql, migration_module: MyApp.Migration
```

#### Role-level lock_timeout

Alternatively, you can set a lock timeout for the user in all commands:

```sql
ALTER ROLE myuser SET lock_timeout = '10s';
```

If you have a different user that runs migrations, this could be a good option for that migration-specific Postgres user. The trade-off is that Elixir developers won't see this timeout as they write migrations and explore the call stack since database role settings are in the database which developers don't usually monitor.

#### Statement Timeout

Another way to ensure safety is to configure your Postgres database with statement timeouts. These timeouts apply to all statements, including migrations and the locks they obtain.

From Postgres docs:

> Abort any statement that takes more than the specified amount of time. If `log_min_error_statement` is set to `ERROR` or lower, the statement that timed out will also be logged. If this value is specified without units, it is taken as milliseconds. A value of zero (the default) disables the timeout.
>
> The timeout is measured from the time a command arrives at the server until it is completed by the server. If multiple SQL statements appear in a single simple-Query message, the timeout is applied to each statement separately. (PostgreSQL versions before 13 usually treated the timeout as applying to the whole query string.) In extended query protocol, the timeout starts running when any query-related message (Parse, Bind, Execute, Describe) arrives, and it is canceled by completion of an Execute or Sync message.

You can specify this configuration for the Postgres user. For example:

```sql
ALTER ROLE myuser SET statement_timeout = '10m';
```

Now any statement automatically times out if it runs for more than 10 minutes; opposed to running indefinitely. This can help if you accidentally run a query that runs the database CPU hot, slowing everything else down; now the unoptimized query will be limited to 10 minutes or else it will fail and be canceled.

Setting this `statement_timeout` requires discipline from the team; if there are runaway queries that fail (for example) at 10 minutes, an exception will likely occur somewhere. You will want to equip your application with sufficient logging, tracing, and reporting so you can replicate the query and the parameters it took to hit the timeout, and ultimately optimize the query. Without this discipline, you risk creating a culture that ignores exceptions.

#### Timeouts for Non-Transactional Migrations

When `@disable_ddl_transaction true` is set, the `after_begin/0` callback is not called, so you cannot rely on it to set timeouts. Instead, set the timeout directly in your migration:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  execute "SET lock_timeout TO '5s'"
  create index("posts", [:slug], concurrently: true)
end
```

Note that `SET` without `LOCAL` sets the timeout for the session. Since there's no transaction, `SET LOCAL` would have no effect.

### Handling Failed Concurrent Operations

When `CREATE INDEX CONCURRENTLY` fails (due to timeout, deadlock, or other errors), PostgreSQL leaves behind an **invalid index**. This index:

- Takes up disk space
- Slows down writes (PostgreSQL still updates it)
- Does not speed up queries (the planner ignores it)

You can find invalid indexes with:

```sql
SELECT indexrelid::regclass AS index_name, indrelid::regclass AS table_name
FROM pg_index WHERE NOT indisvalid;
```

To clean up, drop the invalid index and retry:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  # Drop any invalid index from a previous failed attempt
  execute "DROP INDEX CONCURRENTLY IF EXISTS posts_slug_index"
  create index("posts", [:slug], concurrently: true)
end
```

> #### Caution {: .warning}
>
> Always check for invalid indexes after a failed concurrent migration. They won't go away on their own and can silently degrade write performance.

### Monitoring Locks During Migrations

When running migrations, especially on large tables, it's helpful to monitor for lock contention. You can run this query in a separate session to see blocked queries:

```sql
SELECT
  blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  blocked.wait_event_type,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query,
  now() - blocked.query_start AS blocked_duration
FROM pg_stat_activity blocked
JOIN pg_locks blocked_locks ON blocked.pid = blocked_locks.pid AND NOT blocked_locks.granted
JOIN pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking ON blocking_locks.pid = blocking.pid
WHERE blocked.wait_event_type = 'Lock';
```

This shows you which queries are waiting for locks and what's blocking them. If you see your migration blocking many queries, you may want to cancel it and use a safer approach.

---

This guide was originally published on [Fly.io Phoenix Files](https://fly.io/phoenix-files/anatomy-of-an-ecto-migration/).
