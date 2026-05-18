# Safe Ecto Migrations

A guide on common migration recipes and how to avoid trouble.

## Quick Reference

| Operation | Risk | Safe Approach |
|-----------|------|---------------|
| [Adding an index](#adding-an-index) | Blocks writes | Use `concurrently: true` and disable transactions |
| [Dropping an index](#dropping-an-index) | Postgres blocks reads and writes | Use `concurrently: true` in Postgres; recent MySQL keeps the table available |
| [Adding a reference or foreign key](#adding-a-reference-or-foreign-key) | Blocks writes on both tables | Use `validate: false`, then validate separately |
| [Adding a column with a default value](#adding-a-column-with-a-default-value) | Volatile or expression defaults may rewrite the table | Constant defaults are fast on recent Postgres/MySQL; otherwise add the column first, then set the default |
| [Changing a column's default value](#changing-a-columns-default-value) | Using `modify/3` can force an unnecessary type change | Use raw SQL to change only the default |
| [Changing the type of a column](#changing-the-type-of-a-column) | Table rewrite | Create a new column, migrate data, swap reads, drop the old column |
| [Removing a column](#removing-a-column) | Query failures | Remove it from the schema first, then drop it |
| [Renaming a column](#renaming-a-column) | Query failures | Prefer renaming the schema field and using `source:` |
| [Renaming a table](#renaming-a-table) | Query failures | Prefer renaming the schema module instead |
| [Adding a check constraint](#adding-a-check-constraint) | Full table scan | Create with `validate: false`, then validate separately |
| [Setting NOT NULL on an existing column](#setting-not-null-on-an-existing-column) | Postgres requires a full table scan | Use a check constraint, validate it, then add `NOT NULL` |
| [Adding a JSON column](#adding-a-json-column) | `SELECT DISTINCT` errors in Postgres | Use `:jsonb` instead of `:json` |
| [Removing or replacing a PostgreSQL enum value](#removing-or-replacing-a-postgresql-enum-value) | Removing a value requires replacing the type | Rename directly with `RENAME VALUE` when renaming; otherwise phase app changes, backfill, then replace the type |
| [Adding a PostgreSQL extension](#adding-a-postgresql-extension) | Privilege or extension-specific install requirements | Use `IF NOT EXISTS`; disable transactions only if the extension requires it |

## All Scenarios

The biggest factor in all the scenarios below is **scale**. For 1 million records 
in tables, you may lock writes to the table when creating the column for 
milliseconds which could be acceptable for you. However, once your table has 
100+ million records, the difference becomes seconds which is more likely to be 
felt and cause timeouts. Therefore, err on the side of safety, but 
**always benchmark for your own database**. Also consider the hardware the
database is running: for example, a Raspberry Pi 2B on a microSD will run much slower.

## Adding an index

Creating an index will [block writes](https://www.postgresql.org/docs/current/sql-createindex.html) to the table in Postgres unless you use `CONCURRENTLY`.

In recent MySQL/InnoDB versions, adding a secondary index is an [online DDL operation](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-operations.html) that permits concurrent DML. `FULLTEXT` and `SPATIAL` indexes have additional caveats.

### Bad

```elixir
def change do
  create index("posts", [:slug])

  # This obtains a ShareLock on "posts" which will block writes to the table
end
```

### Good

With Postgres, instead create the index concurrently which does not block writes.
There are two options:

**Option 1**

[Configure the Repo to use advisory locks](`Ecto.Adapters.Postgres#module-migration-options`) for locking migrations while running. Advisory locks are application-controlled database-level locks, and EctoSQL since v3.9.0 provides an option to use this type of lock. This is the safest option as it avoids the trade-off in Option 2.

Disable the DDL transaction in the migration to avoid a database transaction which is not compatible with `CONCURRENTLY` database operations.

```elixir
# in config/config.exs
config MyApp.Repo, migration_lock: :pg_advisory_lock

# in the migration
@disable_ddl_transaction true

def change do
  create index("posts", [:slug], concurrently: true)
end
```

If you're using Phoenix, you will likely need to disable
the migration lock in the CheckRepoStatus plug during dev to avoid hitting and
waiting on the advisory lock with concurrent web processes. You can do this by
adding `migration_lock: false` to the CheckRepoStatus plug in your
`MyAppWeb.Endpoint`.

**Option 2**

Disable the DDL transaction and the migration lock for the migration. By default, EctoSQL with Postgres will run migrations with a DDL transaction and a migration lock which also (by default) uses another transaction. You must disable both of these database transactions to use `CONCURRENTLY`. However, disabling the migration lock will allow competing nodes to try to run the same migration at the same time (eg, in a multi-node Kubernetes environment that runs migrations before startup). Therefore, some nodes may fail startup for a variety of reasons.

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  create index("posts", [:slug], concurrently: true)
end
```

For either option chosen, the migration may still take a while to run, but reads and updates to rows will continue to work. For example, for 100,000,000 rows it took 165 seconds to add run the migration, but SELECTS and UPDATES could occur while it was running.

**Do not have other changes in the same migration**; only create the index concurrently and separate other changes to later migrations.

## Dropping an index

In Postgres, dropping an index blocks reads and writes while acquiring an `ACCESS EXCLUSIVE` lock.

In recent MySQL/InnoDB versions, dropping a secondary index is an online operation that keeps the table available for reads and writes.

### Bad

```elixir
def change do
  drop index("posts", [:slug])
  # Acquires ACCESS EXCLUSIVE lock, blocking all reads and writes
end
```

### Good

Drop the index concurrently to avoid blocking reads and writes:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  drop index("posts", [:slug], concurrently: true)
end
```

Or with advisory locks (preferred):

```elixir
# in config/config.exs
config MyApp.Repo, migration_lock: :pg_advisory_lock

# in the migration
@disable_ddl_transaction true

def change do
  drop index("posts", [:slug], concurrently: true)
end
```

> #### Note {: .info}
>
> Like creating indexes concurrently, dropping concurrently cannot be done inside a transaction. The same caveats about multi-node deployments apply.

## Adding a reference or foreign key

Adding a foreign key blocks writes on both tables.

### Bad

```elixir
def change do
  alter table("posts") do
    add :group_id, references("groups")
    # Obtains a ShareRowExclusiveLock which blocks writes on both tables
  end
end
```


### Good

In the first migration

```elixir
def change do
  alter table("posts") do
    add :group_id, references("groups", validate: false)
    # Obtains a ShareRowExclusiveLock which blocks writes on both tables.
  end
end
```

In the second migration

```elixir
def change do
  execute "ALTER TABLE posts VALIDATE CONSTRAINT group_id_fkey", ""
  # Obtains a ShareUpdateExclusiveLock which doesn't block reads or writes
end
```

> #### Note {: .info}
>
> The down migration is an empty string because PostgreSQL does not have an "unvalidate" operation for constraints. This is safe because validation only confirms existing data meets the constraint—it doesn't modify data. If you need to rollback, the constraint will remain validated, which has no negative impact.

These migrations can be in the same deployment, but make sure they are separate migrations.

**Note on empty tables**: when the table creating the referenced column is empty, you may be able to
create the column and validate at the same time since the time difference would be milliseconds
which may not be noticeable, no matter if you have 1 million or 100 million records in the referenced table.

**Note on populated tables**: the biggest difference depends on your scale. For 1 million records in
both tables, you may lock writes to both tables when creating the column for milliseconds
(you should benchmark for yourself) which could be acceptable for you. However, once your table has
100+ million records, the difference becomes seconds which is more likely to be felt and cause timeouts.
The differentiating metric is the time that both tables are locked from writes. Therefore, err on the side
of safety and separate constraint validation from referenced column creation when there is any data in the table.

## Adding a column with a default value

On PostgreSQL 11+ and recent MySQL/InnoDB versions, adding a column with a constant or literal default is usually a fast metadata change. The main remaining hazards are volatile or expression defaults in Postgres, and MySQL cases where the table cannot use its online DDL fast path.

### Caveats

Note: A constant default is generally safe in:

- [Postgres 11+](https://www.postgresql.org/docs/release/11.0/). Default applies to INSERT since 7.x, and UPDATE since 9.3.
- MySQL 8.0.12+
- MariaDB 10.3.2+

The volatile-expression example below remains unsafe in Postgres.

```elixir
def change do
  alter table("comments") do
    add :approved, :boolean, default: false
    # Safe on recent PostgreSQL/MySQL when the database can use its fast path,
    # but older PostgreSQL versions and some table layouts may still rewrite.
  end
end
```

```elixir
def change do
  alter table("comments") do
    add :some_timestamp, :utc_datetime, default: fragment("now()")
    # A volatile value
  end
end
```

### Good

If you need a conservative approach that also works for older PostgreSQL versions, or you are using a volatile default, add the column first and then alter it to include the default.

First migration:

```elixir
def change do
  alter table("comments") do
    add :approved, :boolean
    # This took 0.27 milliseconds for 100 million rows with no fkeys,
  end
end
```

Second migration:

```elixir
def change do
  execute "ALTER TABLE comments ALTER COLUMN approved SET DEFAULT false",
          "ALTER TABLE comments ALTER COLUMN approved DROP DEFAULT"
  # This took 0.28 milliseconds for 100 million rows with no fkeys,
end
```

Note: we cannot use `Ecto.Migration.modify/3` here as it will include updating the column type as
well unnecessarily, causing Postgres to rewrite the table.

Schema change to read the new column:

```diff
schema "comments" do
+ field :approved, :boolean, default: false
end
```

> #### Note {: .info}
>
> The safe method will not materialize the default value on the column for existing rows because the default was not set when adding the column (avoiding a potential table lock so it can re-write it to _write_ the default). This may affect your queries where you'd expect the value to now be set to your default but is actually `null`. However, the next `UPDATE` operation on the row will materialize the default, additionally Ecto will apply the default on the application side when reading the record. If you want to materialize the value, then you will need to consider [backfilling](backfilling_data.md).

## Changing a column's default value

Changing only a column's default is typically a metadata change in PostgreSQL and MySQL. The real risk in Ecto is using `Ecto.Migration.modify/3`, which also restates the type.

### Bad

```elixir
def change do
  alter table("comments") do
    # Previously, the default was `true`
    modify :approved, :boolean, default: false
    # This also restates the type, which can trigger unnecessary work.
  end
end
```

The issue is that we cannot use `Ecto.Migration.modify/3` as it will include updating the column type as
well unnecessarily, causing Postgres to rewrite the table.

### Good

Execute raw sql instead to alter the default:

```elixir
def change do
  execute "ALTER TABLE comments ALTER COLUMN approved SET DEFAULT false",
          "ALTER TABLE comments ALTER COLUMN approved SET DEFAULT true"
  # This took 0.28 milliseconds for 100 million rows with no fkeys,
end
```

> #### Note {: .info}
>
> This will not update the values of rows previously-set by the old default. This value has been materialized at the time of insert/update and therefore has no distinction between whether it was set by the column `DEFAULT` or set by the original operation.
>
> If you want to update the default of already-written rows, you must distinguish them somehow and modify them with a [backfill](backfilling_data.md)

## Changing the type of a column

Changing the type of a column may cause the table to be rewritten. During this time, reads and writes are blocked in Postgres, and writes are blocked in MySQL and MariaDB.

### Bad

Safe in Postgres:

- increasing length on varchar or removing the limit
- changing varchar to text
- changing text to varchar with no length limit
- Postgres 9.2+ - increasing precision (NOTE: not scale) of decimal or numeric columns. eg, increasing 8,2 to 10,2 is safe. Increasing 8,2 to 8,4 is not safe.
- Postgres 9.2+ - changing decimal or numeric to be unconstrained
- Postgres 12+ - changing timestamp to timestamptz when session TZ is UTC

Safe in MySQL/MariaDB:

- increasing length of varchar from < 255 up to 255.
- increasing length of varchar from > 255 up to max.

```elixir
def change do
  alter table("posts") do
    modify :my_column, :boolean, from: :text
  end
end
```

### Good

Take a phased approach:

1. Create a new column
1. In application code, write to both columns
1. Backfill data from old column to new column
1. In application code, move reads from old column to the new column
1. In application code, remove old column from Ecto schemas.
1. Drop the old column.

## Removing a column

If Ecto is still configured to read a column in any running instances of the application, then queries will fail when loading data into your structs. This can happen in multi-node deployments or if you start the application before running migrations.

### Bad

```elixir
# Without a code change to the Ecto Schema

def change do
  alter table("posts") do
    remove :no_longer_needed_column
  end
end
```


### Good

Safety can be assured if the application code is first updated to remove references to the column so it's no longer loaded or queried. Then, the column can safely be removed from the table.

1. Deploy code change to remove references to the field.
1. Deploy migration change to remove the column.

First deployment:

```diff
# First deploy, in the Ecto schema

defmodule MyApp.Post do
  schema "posts" do
-   column :no_longer_needed_column, :text
  end
end
```

Second deployment:

```elixir
def change do
  alter table("posts") do
    remove :no_longer_needed_column
  end
end
```

## Renaming a column

Ask yourself: "Do I _really_ need to rename a column?". Probably not, but if you must, read on and be aware it requires time and effort.

If Ecto is configured to read a column in any running instances of the application, then queries will fail when loading data into your structs. This can happen in multi-node deployments or if you start the application before running migrations.

There is a shortcut: Don't rename the database column, and instead rename the schema's field name and configure it to point to the database column.

### Bad

```elixir
# In your schema
schema "posts" do
  field :summary, :text
end


# In your migration
def change do
  rename table("posts"), :title, to: :summary
end
```

The time between your migration running and your application getting the new code may encounter trouble.

### Good

**Strategy 1**

Rename the field in the schema only, and configure it to point to the database column and keep the database column the same. Ensure all calling code relying on the old field name is also updated to reference the new field name.

```elixir
defmodule MyApp.MySchema do
  use Ecto.Schema

  schema "weather" do
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :precipitation, :float, source: :prcp
    field :city, :string

    timestamps(type: :naive_datetime_usec)
  end
end
```

```diff
## Update references in other parts of the codebase:
   my_schema = Repo.get(MySchema, "my_id")
-  my_schema.prcp
+  my_schema.precipitation
```

**Strategy 2**

Take a phased approach and use a database view:

1. In the same transaction: (1) Rename the table to a temporary name, (2) Create an updatable database view with the table's original name, selecting all of the table's columns as well as the renaming column selected again as the new name.
1. In application code, change the field source to the new name
1. In the same transaction: (1) Drop the database view, (2) Rename the database table back to the real name, (3) Rename the column to the new name

**Strategy 3**

Take a phased approach and physically rewrite the column:

1. Create a new column
1. In application code, write to both columns
1. Backfill data from old column to new column
1. In application code, move reads from old column to the new column
1. In application code, remove old column from Ecto schemas.
1. Drop the old column.

## Renaming a table

Ask yourself: "Do I _really_ need to rename a table?". Probably not, but if you must, read on and be aware it requires time and effort.

If Ecto is still configured to read a table in any running instances of the application, then queries will fail when loading data into your structs. This can happen in multi-node deployments or if you start the application before running migrations.

There is a shortcut: rename the schema only, and do not change the underlying database table name.

### Bad

```elixir
def change do
  rename table("posts"), to: table("articles")
end
```

### Good

**Strategy 1**

Rename the schema only and all calling code, and don't rename the table:

```diff
- defmodule MyApp.Weather do
+ defmodule MyApp.Forecast do
  use Ecto.Schema

  schema "weather" do
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :precipitation, :float, source: :prcp
    field :city, :string

    timestamps(type: :naive_datetime_usec)
  end
end

# and in calling code:
- weather = MyApp.Repo.get(MyApp.Weather, "my_id")
+ forecast = MyApp.Repo.get(MyApp.Forecast, "my_id")
```

**Strategy 2**

Take a phased approach and use a database view:

For example, rename "weather" to "forecasts"

1. Create an updatable database view of the table with the new name "forecasts"
1. In application code, change the schema source to the updatable view "forecasts"
1. In the same transaction: (1) drop the database view, (2) rename the database table to the intended name, eg "forecasts"

**Strategy 3**

Take a phased approach and physically rewrite the table:

1. Create the new table. This should include creating new constraints (checks and foreign keys) that mimic behavior of the old table.
1. In application code, write to both tables, continuing to read from the old table.
1. Backfill data from old table to new table
1. In application code, move reads from old table to the new table
1. In application code, remove the old table from Ecto schemas.
1. Drop the old table.

## Adding a check constraint

Adding a check constraint blocks reads and writes to the table in Postgres, and blocks writes in MySQL/MariaDB while every row is checked.

### Bad

```elixir
def change do
  create constraint("products", :price_must_be_positive, check: "price > 0")
  # Creating the constraint with validate: true (the default when unspecified)
  # will perform a full table scan and acquires a lock preventing updates
end
```

### Good

There are two operations occurring:

1. Creating a new constraint for new or updating records
1. Validating the new constraint for existing records

If these commands are happening at the same time, it obtains a lock on the table as it validates the entire table and fully scans the table. To avoid this full table scan, we can separate the operations.

In one migration:

```elixir
def change do
  create constraint("products", :price_must_be_positive, check: "price > 0", validate: false)
  # Setting validate: false will prevent a full table scan, and therefore
  # commits immediately.
end
```

In the next migration:

```elixir
def change do
  execute "ALTER TABLE products VALIDATE CONSTRAINT price_must_be_positive", ""
  # Acquires SHARE UPDATE EXCLUSIVE lock, which allows updates to continue
end
```

These can be in the same deployment, but ensure there are 2 separate migrations.

## Setting NOT NULL on an existing column

In Postgres, setting NOT NULL on an existing column requires scanning the table and can block concurrent updates while every row is checked. Recent MySQL/InnoDB versions permit concurrent DML for many NOT NULL changes, though the operation may still rebuild the table.

Just like the Adding a check constraint scenario, there are two operations occurring:

1. Creating a new constraint for new or updating records
1. Validating the new constraint for existing records

To avoid the full table scan, we can separate these two operations.

### Bad

```elixir
def change do
  alter table("products") do
    modify :active, :boolean, null: false
  end
end
```

### Good

Add a check constraint without validating it, backfill data to satiate the constraint and then validate it. This will be functionally equivalent.

In the first migration:

```elixir
# Deployment 1
def change do
  create constraint("products", :active_not_null, check: "active IS NOT NULL", validate: false)
end
```

This will enforce the constraint in all new rows, but not care about existing rows until that row is updated.

You'll likely need a data migration at this point to ensure that the constraint is satisfied.

Then, in the next deployment's migration, we'll enforce the constraint on all rows:

```elixir
# Deployment 2
def change do
  execute "ALTER TABLE products VALIDATE CONSTRAINT active_not_null", ""
end
```

You can then add the NOT NULL to the column after validating the constraint. From the Postgres docs:

> SET NOT NULL may only be applied to a column provided
> none of the records in the table contain a NULL value
> for the column. Ordinarily this is checked during the
> ALTER TABLE by scanning the entire table; however, if
> a valid CHECK constraint is found which proves no NULL
> can exist, then the table scan is skipped.

**However** we cannot use `Ecto.Migration.modify/3`
as it will include updating the column type as well unnecessarily, causing
Postgres to rewrite the table.

```elixir
def change do
  execute "ALTER TABLE products VALIDATE CONSTRAINT active_not_null",
          ""

  execute "ALTER TABLE products ALTER COLUMN active SET NOT NULL",
          "ALTER TABLE products ALTER COLUMN active DROP NOT NULL"

  drop constraint("products", :active_not_null)
end
```

If your constraint fails, then you should consider backfilling data first to cover the gaps in your desired data integrity, then revisit validating the constraint.

## Adding a JSON column

In Postgres, there is no equality operator for the json column type, which can cause errors for existing SELECT DISTINCT queries in your application.

### Bad

```elixir
def change do
  alter table("posts") do
    add :extra_data, :json
  end
end
```

### Good

Use jsonb instead. Some say it's like "json" but "better."

```elixir
def change do
  alter table("posts") do
    add :extra_data, :jsonb
  end
end
```

## Removing or replacing a PostgreSQL enum value

PostgreSQL does not support removing enum values or changing their sort order directly. However, it does support renaming an enum value with `ALTER TYPE ... RENAME VALUE`.

If you only need to rename a value, you can do that directly:

```elixir
def up do
  execute "ALTER TYPE status RENAME VALUE 'obsolete' TO 'draft'"
end
```

For multi-node deployments, still coordinate that rename with application code changes just like any other application-visible rename.

If you need to remove a value, or otherwise replace the enum definition, coordinate application code changes with database changes.

### Bad

```elixir
def change do
  # These operations do not exist in PostgreSQL
  execute "ALTER TYPE status DROP VALUE 'obsolete'"
end
```

### Good

Take a phased approach:

1. **Deploy application code** that handles both old and new enum values (stops writing the value to be removed, reads both old and new values)
2. **Backfill data** to migrate rows from old value to new value (see [backfilling guide](backfilling_data.md))
3. **Deploy migration** to replace the enum type
4. **Deploy application code** to remove handling of old value

First deployment (application code):

```diff
# Stop writing the old value, handle both when reading
defmodule MyApp.Post do
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:status])
-   |> validate_inclusion(:status, ~w(draft obsolete published archived))
+   |> validate_inclusion(:status, ~w(draft published archived))
  end

  # Handle old value when reading
  def display_status(%{status: "obsolete"}), do: "draft"
  def display_status(%{status: status}), do: status
end
```

Second deployment (backfill existing rows):

```elixir
def up do
  execute "UPDATE posts SET status = 'draft' WHERE status = 'obsolete'"
end
```

For large tables, batch this operation. See [backfilling data](backfilling_data.md) for safe approaches.

Third deployment (replace the enum type):

```elixir
def up do
  execute "CREATE TYPE status_new AS ENUM ('draft', 'published', 'archived')"
  execute "ALTER TABLE posts ALTER COLUMN status TYPE status_new USING status::text::status_new"
  execute "DROP TYPE status"
  execute "ALTER TYPE status_new RENAME TO status"
end
```

> #### Warning {: .warning}
>
> The `ALTER COLUMN ... TYPE` operation rewrites the table and blocks reads and writes. For large tables, consider a phased migration using a new column instead.

## Adding a PostgreSQL extension

`CREATE EXTENSION` can usually run inside a transaction. The main concerns are privileges, extension availability, and whether the extension's installation script depends on commands that cannot run inside a transaction block.

### Example

```elixir
def change do
  execute "CREATE EXTENSION \"uuid-ossp\""
end
```

### Good

```elixir
def change do
  execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"",
          "DROP EXTENSION IF EXISTS \"uuid-ossp\""
end
```

> #### Note {: .info}
>
> Creating extensions typically requires superuser privileges. In managed database services (AWS RDS, Heroku), some extensions may not be available.
>
> If an extension complains that it cannot run inside a transaction block, then disable the DDL transaction for that specific migration.

## Credits

Created and written by David Bernheisel with recipes heavily inspired from Andrew Kane and his library [strong_migrations](https://github.com/ankane/strong_migrations).

- [PostgreSQL at Scale by James Coleman](https://medium.com/braintree-product-technology/postgresql-at-scale-database-schema-changes-without-downtime-20d3749ed680)
- [Strong Migrations by Andrew Kane](https://github.com/ankane/strong_migrations)
- [Adding a NOT NULL CONSTRAINT on PG Faster with Minimal Locking by Christophe Escobar](https://medium.com/doctolib/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c)
- [Postgres Runtime Configuration](https://www.postgresql.org/docs/current/runtime-config-client.html)

Special thanks for sponsorship: Fly.io
