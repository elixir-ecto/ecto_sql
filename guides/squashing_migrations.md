# Squashing Migrations

If you have a long list of migrations, sometimes it can take a while to migrate
each of those files every time the project is reset or spun up by a new
developer. Thankfully, Ecto comes with mix tasks to `dump` and `load` a database
structure which will represent the state of the database up to a certain point
in time, not including content.

- `mix ecto.dump`
- `mix ecto.load`

Schema dumping and loading is only supported by external binaries `pg_dump` and
`mysqldump`, which are used by the Postgres, MyXQL, and MySQL Ecto adapters (not
supported in MSSQL adapter).

For example:

```
20210101000000 - First Migration
20210201000000 - Second Migration
20210701000000 - Third Migration <-- we are here now. run `mix ecto.dump`
```

We can "squash" the migrations up to the current day which will effectively
fast-forward migrations to that structure. The Ecto Migrator will detect that
the database is already migrated to the third migration, and so it begins there
and migrates forward.

Let's add a new migration:

```
20210101000000 - First Migration
20210201000000 - Second Migration
20210701000000 - Third Migration <-- `structure.sql` represents up to here
20210801000000 - New Migration <-- This is where migrations will begin
```

The new migration will still run, but the first-through-third migrations will
not need to be run since the structure already represents the changes applied by
those migrations. At this point, you can safely delete the first, second, and
third migration files or keep them for historical auditing.

Let's make this work:

1. Run `mix ecto.dump` which will dump the current structure into
   `priv/repo/structure.sql` by default. Check `mix help ecto.dump` for more
   options.
2. During project setup with an empty database, run `mix ecto.load` to load
   `structure.sql`.
3. Run `mix ecto.migrate` to run any additional migrations created after the
   structure was dumped.

To simplify these actions into one command, we can leverage mix aliases:

```elixir
# mix.exs

defp aliases do
  [
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    "ecto.setup": ["ecto.load", "ecto.migrate"],
    # ...
  ]
end
```

Now you can run `mix ecto.setup` and it will load the database structure and run
remaining migrations. Or, run `mix ecto.reset` and it will drop and run setup.
Of course, you can continue running `mix ecto.migrate` as you create them.