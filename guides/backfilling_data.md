# Backfilling Data

When I say "backfilling data", I mean that as any attempt to change data in bulk. This can happen in code through migrations, application code, UIs that allow multiple selections and updates, or in a console connected to a running application. Since bulk changes affect a lot of data, it's always a good idea to have the code reviewed before it runs. You also want to check that it runs efficiently and does not overwhelm the database. Ideally, it's nice when the code is written to be safe to re-run. For these reasons, please don't change data in bulk through a console!

We're going to focus on bulk changes executed though Ecto migrations, but the same principles are applicable to any case where bulk changes are being made. Typical scenarios where you might need to run data migrations is when you need to fill in data for records that already exist (hence, backfilling data). This usually comes up when table structures are changed in the database.

Some examples of backfilling:

- Populating data into a new column
- Changing a column to make it required. May require changing existing rows to set a value.
- Splitting one database table into several
- Fixing bad data

For simplicity, we are using `Ecto.Migrator` to run our data migrations, but it's important to not let these migrations break developers' environments over time (more on this below). If using migrations to change data is a normal process that happens regularly, then you may consider exploring a migration system outside of `Ecto.Migrator` that is observable, hooks into error reporting, metrics, and allows for dry runs. This guide is intended as a starting point, and since Ecto ships with a migration runner, we'll leverage it to also run the data migrations.

There are both bad and good ways to write these data migrations. Let explore some:

## Bad

In the following example, a migration references the schema `MyApp.MySchema`.

```elixir
defmodule MyApp.Repo.DataMigrations.BackfillPosts do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table("posts") do
      add :new_data, :text
    end

    flush()

    MyApp.MySchema
    |> where(new_data: nil)
    |> MyApp.Repo.update_all(set: [new_data: "some data"])
  end
end
```

The problem is the code and schema may change over time. However, migrations are using a snapshot of your schemas at the time it's written. In the future, many assumptions may no longer be true. For example, the new_data column may not be present anymore in the schema causing the query to fail if this migration is run months later.

Additionally, in your development environment, you might have 10 records to migrate; in staging, you might have 100; in production, you might have 1 billion to migrate. Scaling your approach matters.

Ultimately, there are several bad practices here:

1. The Ecto schema in the query may change after this migration was written.
1. If you try to backfill the data all at once, it may exhaust the database memory and/or CPU if it's changing a large data set.
1. Backfilling data inside a transaction for the migration locks row updates for the duration of the migration, even if you are updating in batches.
1. Disabling the transaction for the migration and only batching updates may still spike the database CPU to 100%, causing other concurrent reads or writes to time out.

##  Good

There are four keys to backfilling safely:

1. running outside a transaction
1. batching
1. throttling
1. resiliency

As we've learned in this guide, it's straight-forward to disable the migration transactions. Add these options to the migration:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true
```

Batching our data migrations still has several challenges.

We'll start with how do we paginate efficiently: `LIMIT`/`OFFSET` by itself is an expensive query for large tables (they start fast, but slow to a crawl when in the later pages of the table), so we must find another way to paginate. Since we cannot use a database transaction, this also implies we cannot leverage cursors since they require a transaction. This leaves us with [keyset pagination](https://www.citusdata.com/blog/2016/03/30/five-ways-to-paginate/).

For querying and updating the data, there are two ways to "snapshot" your schema at the time of the migration. We'll use both options below in the examples:

1. Execute raw SQL that represents the table at that moment. Do not use Ecto schemas. Prefer this approach when you can. Your application's Ecto schemas will change over time, but your migration should not, therefore it's not a true snapshot of the data at the time.
1. Write a small Ecto schema module inside the migration that only uses what you need. Then use that in your data migration. This is helpful if you prefer the Ecto API and decouples from your application's Ecto schemas as it evolves separately.

For throttling, we can simply add a `Process.sleep(@throttle)` for each page.

For resiliency, we need to ensure that we handle errors without losing our progress. You don't want to migrate the same data twice! Most data migrations I have run find some records in a state that I wasn't expecting. This causes the data migration to fail. When the data migration stops, that means I have to write a little bit more code to handle that scenario, and re-run the migration. Every time the data migration is re-run, it should pick up where it left off without revisiting already-migrated records.

Finally, to manage these data migrations separately, we need to:

1. Store data migrations separately from your schema migrations.
1. Run the data migrations manually.

To achieve this, be inspired by [Ecto's documentation on creating a Release module](`Ecto.Migrator`), and extend your release module to allow options to pass into `Ecto.Migrator` that specifies the version to migrate and the data migrations' file path, for example:

```elixir
defmodule MyApp.Release do
  # ...
  @doc """
  Migrate data in the database. Defaults to migrating to the latest, `[all: true]`
  Also accepts `[step: 1]`, or `[to: 20200118045751]`
  """
  def migrate_data(opts \\ [all: true]) do
    for repo <- repos() do
      path = Ecto.Migrator.migrations_path(repo, "data_migrations")
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, path, :up, opts))
    end
  end
end
```

## Batching Deterministic Data

If the data can be queried with a condition that is removed after update then you can repeatedly query the data and update the data until the query result is empty. For example, if a column is currently null and will be updated to not be null, then you can query for the null records and pick up where you left off.

Here's how we can manage the backfill:

1. Disable migration transactions.
1. Use keyset pagination: Order the data, find rows greater than the last mutated row and limit by batch size.
1. For each page, mutate the records.
1. Check for failed updates and handle it appropriately.
1. Use the last mutated record's ID as the starting point for the next page. This helps with resiliency and prevents looping on the same record over and over again.
1. Arbitrarily sleep to throttle and prevent exhausting the database.
1. Rinse and repeat until there are no more records

For example:

```bash
mix ecto.gen.migration --migrations-path=priv/repo/data_migrations backfill_posts
```

And modify the migration:

```elixir
defmodule MyApp.Repo.DataMigrations.BackfillPosts do
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 1000
  @throttle_ms 100

  def up do
    throttle_change_in_batches(&page_query/1, &do_change/1)
  end

  def down, do: :ok

  def do_change(batch_of_ids) do
    {_updated, results} = repo().update_all(
      from(r in "weather", select: r.id, where: r.id in ^batch_of_ids),
      [set: [approved: true]],
      log: :info
    )
    not_updated = batch_of_ids -- results
    Enum.each(not_updated, &handle_non_update/1)
    Enum.sort(results)
  end

  def page_query(last_id) do
    # Notice how we do not use Ecto schemas here.
    from(
      r in "weather",
      select: r.id,
      where: is_nil(r.approved) and r.id > ^last_id,
      order_by: [asc: r.id],
      limit: @batch_size
    )
  end

  # If you have integer IDs, default last_pos = 0
  # If you have binary IDs, default last_pos = "00000000-0000-0000-0000-000000000000"
  defp throttle_change_in_batches(query_fun, change_fun, last_pos \\ 0)
  defp throttle_change_in_batches(_query_fun, _change_fun, nil), do: :ok
  defp throttle_change_in_batches(query_fun, change_fun, last_pos) do
    case repo().all(query_fun.(last_pos), [log: :info, timeout: :infinity]) do
      [] ->
        :ok

      ids ->
        results = change_fun.(List.flatten(ids))
        next_page = List.first(results)
        Process.sleep(@throttle_ms)
        throttle_change_in_batches(query_fun, change_fun, next_page)
    end
  end

  defp handle_non_update(id) do
    raise "#{inspect(id)} was not updated"
  end
end
```

## Batching Arbitrary Data

If the data being updated does not indicate it's already been updated, then we need to take a snapshot of the current data and store it temporarily. For example, if all rows should increment a column's value by 10, how would you know if a record was already updated? You could load a list of IDs into the application during the migration, but what if the process crashes? Instead we're going to keep the data we need in the database.

To do this, it works well if we can pick a specific point in time where all records _after_ that point in time do not need adjustment. This happens when you realize a bug was creating bad data and after the bug was fixed and deployed, all new entries are good and should not be touched as we clean up the bad data. For this example, we'll use `inserted_at` as our marker. Let's say that the bug was fixed on a midnight deploy on 2021-08-22.

Here's how we'll manage the backfill:

1. Create a "temporary" table. In this example, we're creating a real table that we'll drop at the end of the data migration. In Postgres, there are [actual temporary tables](https://www.postgresql.org/docs/12/sql-createtable.html) that are discarded after the session is over; we're not using those because we need resiliency in case the data migration encounters an error. The error would cause the session to be over, and therefore the temporary table tracking progress would be lost. Real tables don't have this problem. Likewise, we don't want to store IDs in application memory during the migration for the same reason.
1. Populate that temporary table with IDs of records that need to update. This query only requires a read of the current records, so there are no consequential locks occurring when populating, but be aware this could be a lengthy query. Populating this table can occur at creation or afterwards; in this example we'll populate it at table creation.
1. Ensure there's an index on the temporary table so it's fast to delete IDs from it. I use an index instead of a primary key because it's easier to re-run the migration in case there's an error. There isn't a straight-forward way to `CREATE IF NOT EXIST` on a primary key; but you can do that easily with an index.
1. Use keyset pagination to pull batches of IDs from the temporary table. Do this inside a database transaction and lock records for updates. Each batch should read and update within milliseconds, so this should have little impact on concurrent reads and writes.
1. For each batch of records, determine the data changes that need to happen. This can happen for each record.
1. [Upsert](https://wiki.postgresql.org/wiki/UPSERT) those changes to the real table. This insert will include the ID of the record that already exists and a list of attributes to change for that record. Since these insertions will conflict with existing records, we'll instruct Postgres to replace certain fields on conflicts.
1. Delete those IDs from the temporary table since they're updated on the real table. Close the database transaction for that batch.
1. Throttle so we don't overwhelm the database, and also give opportunity to other concurrent processes to work.
1. Rinse and repeat until the temporary table is empty.
1. Finally, drop the temporary table when empty.

Let's see how this can work:

```bash
mix ecto.gen.migration --migrations-path=priv/repo/data_migrations backfill_weather
```

Modify the migration:

```elixir
# Both of these modules are in the same migration file
# In this example, we'll define a new Ecto Schema that is a snapshot
# of the current underlying table and no more.
defmodule MyApp.Repo.DataMigrations.BackfillWeather.MigratingSchema do
  use Ecto.Schema

  # Copy of the schema at the time of migration
  schema "weather" do
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp, :float
    field :city, :string

    timestamps(type: :naive_datetime_usec)
  end
end

defmodule MyApp.Repo.DataMigrations.BackfillWeather do
  use Ecto.Migration
  import Ecto.Query
  alias MyApp.Repo.DataMigrations.BackfillWeather.MigratingSchema

  @disable_ddl_transaction true
  @disable_migration_lock true
  @temp_table_name "records_to_update"
  @batch_size 1000
  @throttle_ms 100

  def up do
    repo().query!("""
    CREATE TABLE IF NOT EXISTS "#{@temp_table_name}" AS
    SELECT id FROM weather WHERE inserted_at < '2021-08-21T00:00:00'
    """, [], log: :info, timeout: :infinity)
    flush()

    create_if_not_exists index(@temp_table_name, [:id])
    flush()

    throttle_change_in_batches(&page_query/1, &do_change/1)

    # You may want to check if it's empty before dropping it.
    # Since we're raising an exception on non-updates
    # we don't have to do that in this example.
    drop table(@temp_table_name)
  end

  def down, do: :ok

  def do_change(batch_of_ids) do
    # Wrap in a transaction to momentarily lock records during read/update
    repo().transaction(fn ->
      mutations =
        from(
          r in MigratingSchema,
          where: r.id in ^batch_of_ids,
          lock: "FOR UPDATE"
        )
        |> repo().all()
        |> Enum.reduce([], &mutation/2)

      # Don't be fooled by the name `insert_all`, this is actually an upsert
      # that will update existing records when conflicting; they should all
      # conflict since the ID is included in the update.

      {_updated, results} = repo().insert_all(
        MigratingSchema,
        mutations,
        returning: [:id],
        # Alternatively, {:replace_all_except, [:id, :inserted_at]}
        on_conflict: {:replace, [:temp_lo, :updated_at]},
        conflict_target: [:id],
        placeholders: %{now: NaiveDateTime.utc_now()},
        log: :info
      )
      results = results |> Enum.map(& &1.id) |> Enum.sort()

      not_updated =
        mutations
        |> Enum.map(& &1[:id])
        |> MapSet.new()
        |> MapSet.difference(MapSet.new(results))
        |> MapSet.to_list()

      Enum.each(not_updated, &handle_non_update/1)
      repo().delete_all(from(r in @temp_table_name, where: r.id in ^results))

      results
    end)
  end

  def mutation(record, mutations_acc) do
    # This logic can be whatever you need; we'll just do something simple
    # here to illustrate

    if record.temp_hi > 1 do
      # No updated needed
      mutations_acc
    else
      # Upserts don't update autogenerated fields like timestamps, so be sure
      # to update them yourself. The inserted_at value should never be used
      # since all these records are already inserted, and we won't replace
      # this field on conflicts; we just need it to satisfy table constraints.
      [%{
        id: record.id,
        temp_lo: record.temp_hi - 10,
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now}
      } | mutations_acc]
    end
  end

  def page_query(last_id) do
    from(
      r in @temp_table_name,
      select: r.id,
      where: r.id > ^last_id,
      order_by: [asc: r.id],
      limit: @batch_size
    )
  end

  defp handle_non_update(id) do
    raise "#{inspect(id)} was not updated"
  end

  # If you have integer IDs, fallback last_pod = 0
  # If you have binary IDs, fallback last_pos = "00000000-0000-0000-0000-000000000000"
  defp throttle_change_in_batches(query_fun, change_fun, last_pos \\ 0)
  defp throttle_change_in_batches(_query_fun, _change_fun, nil), do: :ok
  defp throttle_change_in_batches(query_fun, change_fun, last_pos) do
    case repo().all(query_fun.(last_pos), [log: :info, timeout: :infinity]) do
      [] ->
        :ok

      ids ->
        case change_fun.(List.flatten(ids)) do
          {:ok, results} ->
            next_page = List.first(results)
            Process.sleep(@throttle_ms)
            throttle_change_in_batches(query_fun, change_fun, next_page)
          error ->
            raise error
        end
    end
  end
end
```

---

This guide was originally published on [Fly.io Phoenix Files](https://fly.io/phoenix-files/backfilling-data/).
