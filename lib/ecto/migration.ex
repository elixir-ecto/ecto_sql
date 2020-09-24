defmodule Ecto.Migration do
  @moduledoc """
  Migrations are used to modify your database schema over time.

  This module provides many helpers for migrating the database,
  allowing developers to use Elixir to alter their storage in
  a way that is database independent.

  Migrations typically provide two operations: `up` and `down`,
  allowing us to migrate the database forward or roll it back
  in case of errors.

  In order to manage migrations, Ecto creates a table called
  `schema_migrations` in the database, which stores all migrations
  that have already been executed. You can configure the name of
  this table with the `:migration_source` configuration option.

  You can configure a different database for the table that
  manages your migrations by setting the `:migration_repo`
  configuration option to a different repository.

  Ecto also locks the `schema_migrations` table when running
  migrations, guaranteeing two different servers cannot run the same
  migration at the same time.

  ## Creating your first migration

  Migrations are defined inside the "priv/REPO/migrations" where REPO
  is the last part of the repository name in underscore. For example,
  migrations for `MyApp.Repo` would be found in "priv/repo/migrations".
  For `MyApp.CustomRepo`, it would be found in "priv/custom_repo/migrations".

  Each file in the migrations directory has the following structure:

      NUMBER_NAME.exs

  The NUMBER is a unique number that identifies the migration. It is
  usually the timestamp of when the migration was created. The NAME
  must also be unique and it quickly identifies what the migration
  does. For example, if you need to track the "weather" in your system,
  you can start a new file at "priv/repo/migrations/20190417140000_add_weather_table.exs"
  that will have the following contents:

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def up do
          create table("weather") do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end

        def down do
          drop table("weather")
        end
      end

  The `up/0` function is responsible to migrate your database forward.
  the `down/0` function is executed whenever you want to rollback.
  The `down/0` function must always do the opposite of `up/0`.
  Inside those functions, we invoke the API defined in this module,
  you will find conveniences for managing tables, indexes, columns,
  references, as well as running custom SQL commands.

  To run a migration, we generally use Mix tasks. For example, you can
  run the migration above by going to the root of your project and
  typing:

      $ mix ecto.migrate

  You can also roll it back by calling:

      $ mix ecto.rollback --step 1

  Note rollback requires us to say how much we want to rollback.
  On the other hand, `mix ecto.migrate` will always run all pending
  migrations.

  In practice, we don't create migration files by hand either, we
  typically use `mix ecto.gen.migration` to generate the file with
  the proper timestamp and then we just fill in its contents:

      $ mix ecto.gen.migration add_weather_table

  ## Mix tasks

  As seen above, Ecto provides many Mix tasks to help developers work
  with migrations. We summarize them below:

    * `mix ecto.gen.migration` - generates a
      migration that the user can fill in with particular commands
    * `mix ecto.migrate` - migrates a repository
    * `mix ecto.migrations` - shows all migrations and their status
    * `mix ecto.rollback` - rolls back a particular migration

  Run `mix help COMMAND` for more information on a particular command.
  For a lower level API for running migrations, see `Ecto.Migrator`.

  ## Change

  Having to write both `up/0` and `down/0` functions for every
  migration is tedious and error prone. For this reason, Ecto allows
  you to defined a `change/0` callback with all of the code you want
  to execute when migrating and Ecto will automatically figure out
  the `down/0` for you. For example, the migration above can be
  written as:

      defmodule MyRepo.Migrations.AddWeatherTable do
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

  However, note that not all commands are reversible. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.

  A notable command in this regard is `execute/2`, which is reversible in
  `change/0` by accepting a pair of plain SQL strings. The first is run on
  forward migrations (`up/0`) and the second when rolling back (`down/0`).

  If `up/0` and `down/0` are implemented in a migration, they take precedence,
  and `change/0` isn't invoked.

  ## Field Types

  The Ecto primitive types are mapped to the appropriate database
  type by the various database adapters. For example, `:string` is
  converted to `:varchar`, `:binary` to `:bytea` or `:blob`, and so on.

  Similarly, you can pass any field type supported by your database
  as long as it maps to an Ecto type. For instance, for an Ecto schema
  with the field `:string`, the database migration type can be any of
  `:text`, `:char` or `:varchar` (the default).

  In particular, note that:

    * the `:string` type in migrations by default has a limit of 255 characters.
      If you need more or less characters, pass the `:size` option, such
      as `add :field, :string, size: 10`. If you don't want to impose a limit,
      most databases support a `:text` type or similar

    * the `:binary` type in migrations by default has no size limit. If you want
      to impose a limit, pass the `:size` option accordingly. In MySQL, passing
      the size option changes the underlying field from "blob" to "varbinary"

  Remember, atoms can contain arbitrary characters by enclosing in
  double quotes the characters following the colon. So, if you want to use a
  field type with database-specific options, you can pass atoms containing
  these options like `:"int unsigned"`, `:"time without time zone"`, etc.

  ## Executing and flushing

  Instructions inside of migrations are not executed immediately. Instead
  they are performed after the relevant `up`, `change`, or `down` callback
  terminates.

  However, in some situations you may want to guarantee that all of the
  previous steps have been executed before continuing. This is useful when
  you need to apply a set of changes to the table before continuing with the
  migration. This can be done with `flush/0`:

      def up do
        ...
        flush()
        ...
      end

  However `flush/0` will raise if it would be called from `change` function when doing a rollback.
  To avoid that we recommend to use `execute/2` with anonymous functions instead.
  For more information and example usage please take a look at `execute/2` function.

  ## Comments

  Migrations where you create or alter a table support specifying table
  and column comments. The same can be done when creating constraints
  and indexes. Not all databases support this feature.

      def up do
        create index("posts", [:name], comment: "Index Comment")
        create constraint("products", "price_must_be_positive", check: "price > 0", comment: "Constraint Comment")
        create table("weather", prefix: "north_america", comment: "Table Comment") do
          add :city, :string, size: 40, comment: "Column Comment"
          timestamps()
        end
      end

  ## Repo configuration

  The following migration configuration options are available for a given repository:

    * `:migration_source` - Version numbers of migrations will be saved in a
      table named `schema_migrations` by default. You can configure the name of
      the table via:

          config :app, App.Repo, migration_source: "my_migrations"

    * `:migration_primary_key` - By default, Ecto uses the `:id` column with type
      `:bigserial`, but you can configure it via:

          config :app, App.Repo, migration_primary_key: [name: :uuid, type: :binary_id]

          config :app, App.Repo, migration_primary_key: false

    * `:migration_foreign_key` - By default, Ecto uses the migration_primary_key type
      for foreign keys when references/2 is used, but you can configure it via:

          config :app, App.Repo, migration_foreign_key: [column: :uuid, type: :binary_id]

    * `:migration_timestamps` - By default, Ecto uses the `:naive_datetime` type, but
      you can configure it via:

          config :app, App.Repo, migration_timestamps: [type: :utc_datetime]

    * `:migration_lock` - By default, Ecto will lock the migration table. This allows
      multiple nodes to attempt to run migrations at the same time but only one will
      succeed. You can disable the `migration_lock` by setting it to `nil`:

          config :app, App.Repo, migration_lock: nil

    * `:migration_default_prefix` - Ecto defaults to `nil` for the database prefix for
      migrations, but you can configure it via:

          config :app, App.Repo, migration_default_prefix: "my_prefix"

    * `:migration_repo` - The migration repository is where the table managing the
      migrations will be stored (`migration_source` defines the table name). It defaults
      to the given repository itself but you can configure it via:

          config :app, App.Repo, migration_repo: App.MigrationRepo

    * `:priv` - the priv directory for the repo with the location of important assets,
      such as migrations. For a repository named `MyApp.FooRepo`, `:priv` defaults to
      "priv/foo_repo" and migrations should be placed at "priv/foo_repo/migrations"

    * `:start_apps_before_migration` - A list of applications to be started before
      running migrations. Used by `Ecto.Migrator.with_repo/3` and the migration tasks:

          config :app, App.Repo, start_apps_before_migration: [:ssl, :some_custom_logger]

  ## Prefixes

  Migrations support specifying a table prefix or index prefix which will
  target either a schema (if using PostgreSQL) or a different database (if using
  MySQL). If no prefix is provided, the default schema or database is used.

  Any reference declared in the table migration refers by default to the table
  with the same declared prefix. The prefix is specified in the table options:

      def up do
        create table("weather", prefix: "north_america") do
          add :city,    :string, size: 40
          add :temp_lo, :integer
          add :temp_hi, :integer
          add :prcp,    :float
          add :group_id, references(:groups)

          timestamps()
        end

        create index("weather", [:city], prefix: "north_america")
      end

  Note: if using MySQL with a prefixed table, you must use the same prefix
  for the references since cross-database references are not supported.

  When using a prefixed table with either MySQL or PostgreSQL, you must use the
  same prefix for the index field to ensure that you index the prefix-qualified
  table.

  ## Transaction Callbacks

  If possible, each migration runs inside a transaction. This is true for Postgres,
  but not true for MySQL, as the latter does not support DDL transactions.

  In some rare cases, you may need to execute some common behavior after beginning
  a migration transaction, or before commiting that transaction. For instance, one
  might desire to set a `lock_timeout` for each lock in the migration transaction.

  You can do so by defining `c:after_begin/0` and `c:before_commit/0` callbacks to
  your migration.

  However, if you need do so for every migration module, implement this callback
  for every migration can be quite repetitive. Luckily, you can handle this by
  providing your migration module:

      defmodule MyApp.Migration do
        defmacro __using__(_) do
          quote do
            use Ecto.Migration

            def after_begin() do
              repo().query! "SET lock_timeout TO '5s'", "SET lock_timeout TO '10s'"
            end
          end
        end
      end

  Then in your migrations you can `use MyApp.Migration` to share this behavior
  among all your migrations.
  """

  @doc """
  Migration code to run immediately after the transaction is opened.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback after_begin() :: term

  @doc """
  Migration code to run immediately before the transaction is closed.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback before_commit() :: term
  @optional_callbacks after_begin: 0, before_commit: 0

  defmodule Index do
    @moduledoc """
    Used internally by adapters.

    To define an index in a migration, see `Ecto.Migration.index/3`.
    """
    defstruct table: nil,
              prefix: nil,
              name: nil,
              columns: [],
              unique: false,
              concurrently: false,
              using: nil,
              include: [],
              where: nil,
              comment: nil,
              options: nil

    @type t :: %__MODULE__{
      table: String.t,
      prefix: atom,
      name: atom,
      columns: [atom | String.t],
      unique: boolean,
      concurrently: boolean,
      using: atom | String.t,
      include: [atom | String.t],
      where: atom | String.t,
      comment: String.t | nil,
      options: String.t
    }
  end

  defmodule Table do
    @moduledoc """
    Used internally by adapters.

    To define a table in a migration, see `Ecto.Migration.table/2`.
    """
    defstruct name: nil, prefix: nil, comment: nil, primary_key: true, engine: nil, options: nil
    @type t :: %__MODULE__{name: String.t, prefix: atom | nil, comment: String.t | nil, primary_key: boolean,
                           engine: atom, options: String.t}
  end

  defmodule Reference do
    @moduledoc """
    Used internally by adapters.

    To define a reference in a migration, see `Ecto.Migration.references/2`.
    """
    defstruct name: nil, prefix: nil, table: nil, column: :id, type: :bigserial, on_delete: :nothing, on_update: :nothing, validate: true
    @type t :: %__MODULE__{table: String.t, prefix: atom | nil, column: atom, type: atom, on_delete: atom, on_update: atom, validate: boolean}
  end

  defmodule Constraint do
    @moduledoc """
    Used internally by adapters.

    To define a constraint in a migration, see `Ecto.Migration.constraint/3`.
    """
    defstruct name: nil, table: nil, check: nil, exclude: nil, prefix: nil, comment: nil, validate: true
    @type t :: %__MODULE__{name: atom, table: String.t, prefix: atom | nil,
                           check: String.t | nil, exclude: String.t | nil, comment: String.t | nil, validate: boolean}
  end

  defmodule Command do
    @moduledoc """
    Used internally by adapters.

    This represents the up and down legs of a reversible raw command
    that is usually defined with `Ecto.Migration.execute/1`.

    To define a reversible command in a migration, see `Ecto.Migration.execute/2`.
    """
    defstruct up: nil, down: nil
    @type t :: %__MODULE__{up: String.t, down: String.t}
  end

  alias Ecto.Migration.Runner

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration
      @disable_ddl_transaction false
      @disable_migration_lock false
      @before_compile Ecto.Migration
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __migration__ do
        [
          disable_ddl_transaction: @disable_ddl_transaction,
          disable_migration_lock: @disable_migration_lock
        ]
      end
    end
  end

  @doc """
  Creates a table.

  By default, the table will also include an `:id` primary key field that
  has a type of `:bigserial`. Check the `table/2` docs for more information.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
        add :body,  :text

        timestamps()
      end

  """
  defmacro create(object, do: block) do
    expand_create(object, :create, block)
  end

  @doc """
  Creates a table if it does not exist.

  Works just like `create/2` but does not raise an error when the table
  already exists.
  """
  defmacro create_if_not_exists(object, do: block) do
    expand_create(object, :create_if_not_exists, block)
  end

  defp expand_create(object, command, block) do
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({unquote(command), Ecto.Migration.__prefix__(table)})

      if primary_key = table.primary_key && Ecto.Migration.__primary_key__() do
        {name, type, opts} = primary_key
        add(name, type, opts)
      end

      unquote(block)
      Runner.end_command()
      table
    end
  end

  @doc """
  Alters a table.

  ## Examples

      alter table("posts") do
        add :summary, :text
        modify :title, :text
        remove :views
      end

  """
  defmacro alter(object, do: block) do
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({:alter, Ecto.Migration.__prefix__(table)})
      unquote(block)
      Runner.end_command()
    end
  end

  @doc """
  Creates one of the following:

    * an index
    * a table with only the :id primary key
    * a constraint

  When reversing (in a `change/0` running backwards), indexes are only dropped
  if they exist, and no errors are raised. To enforce dropping an index, use
  `drop/1`.

  ## Examples

      create index("posts", [:name])
      create table("version")
      create constraint("products", "price_must_be_positive", check: "price > 0")

  """
  def create(%Index{} = index) do
    Runner.execute {:create, __prefix__(index)}
    index
  end

  def create(%Constraint{} = constraint) do
    Runner.execute {:create, __prefix__(constraint)}
    constraint
  end

  def create(%Table{} = table) do
    do_create table, :create
    table
  end

  @doc """
  Creates an index or a table with only `:id` field if one does not yet exist.

  ## Examples

      create_if_not_exists index("posts", [:name])

      create_if_not_exists table("version")

  """
  def create_if_not_exists(%Index{} = index) do
    Runner.execute {:create_if_not_exists, __prefix__(index)}
  end

  def create_if_not_exists(%Table{} = table) do
    do_create table, :create_if_not_exists
  end

  defp do_create(table, command) do
    columns =
      if primary_key = table.primary_key && Ecto.Migration.__primary_key__() do
        {name, type, opts} = primary_key
        [{:add, name, type, opts}]
      else
        []
      end

    Runner.execute {command, __prefix__(table), columns}
  end

  @doc """
  Drops one of the following:

    * an index
    * a table
    * a constraint

  ## Examples

      drop index("posts", [:name])
      drop table("posts")
      drop constraint("products", "price_must_be_positive")

  """
  def drop(%{} = index_or_table_or_constraint) do
    Runner.execute {:drop, __prefix__(index_or_table_or_constraint)}
    index_or_table_or_constraint
  end

  @doc """
  Drops a table or index if it exists.

  Does not raise an error if the specified table or index does not exist.

  ## Examples

      drop_if_exists index("posts", [:name])
      drop_if_exists table("posts")

  """
  def drop_if_exists(%{} = index_or_table) do
    Runner.execute {:drop_if_exists, __prefix__(index_or_table)}
    index_or_table
  end

  @doc """
  Returns a table struct that can be given to `create/2`, `alter/2`, `drop/1`,
  etc.

  ## Examples

      create table("products") do
        add :name, :string
        add :price, :decimal
      end

      drop table("products")

      create table("products", primary_key: false) do
        add :name, :string
        add :price, :decimal
      end

  ## Options

    * `:primary_key` - when `false`, a primary key field is not generated on table
      creation.
    * `:engine` - customizes the table storage for supported databases. For MySQL,
      the default is InnoDB.
    * `:prefix` - the prefix for the table. This prefix will automatically be used
      for all constraints and references defined for this table unless explicitly
      overridden in said constraints/references.
    * `:options` - provide custom options that will be appended after the generated
      statement. For example, "WITH", "INHERITS", or "ON COMMIT" clauses.

  """
  def table(name, opts \\ [])

  def table(name, opts) when is_atom(name) do
    table(Atom.to_string(name), opts)
  end

  def table(name, opts) when is_binary(name) and is_list(opts) do
    struct(%Table{name: name}, opts)
  end

  @doc ~S"""
  Returns an index struct that can be given to `create/1`, `drop/1`, etc.

  Expects the table name as the first argument and the index field(s) as
  the second. The fields can be atoms, representing columns, or strings,
  representing expressions that are sent as-is to the database.

  ## Options

    * `:name` - the name of the index. Defaults to "#{table}_#{column}_index".
    * `:unique` - indicates whether the index should be unique. Defaults to
      `false`.
    * `:concurrently` - indicates whether the index should be created/dropped
      concurrently.
    * `:using` - configures the index type.
    * `:prefix` - specify an optional prefix for the index.
    * `:where` - specify conditions for a partial index.
    * `:include` - specify fields for a covering index. This is not supported
      by all databases. For more information on PostgreSQL support, please
      [read the official docs](https://www.postgresql.org/docs/11/indexes-index-only-scans.html).

  ## Adding/dropping indexes concurrently

  PostgreSQL supports adding/dropping indexes concurrently (see the
  [docs](http://www.postgresql.org/docs/9.4/static/sql-createindex.html)).
  However, this feature does not work well with the transactions used by
  Ecto to guarantee integrity during migrations.

  Therefore, to migrate indexes concurrently, you need to set
  both `@disable_ddl_transaction` and `@disable_migration_lock` to true:

      defmodule MyRepo.Migrations.CreateIndexes do
        use Ecto.Migration
        @disable_ddl_transaction true
        @disable_migration_lock true

        def change do
          create index("posts", [:slug], concurrently: true)
        end
      end

  Disabling DDL transactions removes the guarantee that all of the changes
  in the migration will happen at once. Disabling the migration lock removes
  the guarantee only a single node will run a given migration if multiple
  nodes are attempting to migrate at the same time.

  Since running migrations outside a transaction and without locks can be
  dangerous, consider performing very few operations in migrations that add
  concurrent indexes. We recommend to run migrations with concurrent indexes
  in isolation and disable those features only temporarily.

  ## Index types

  When creating an index, the index type can be specified with the `:using`
  option. The `:using` option can be an atom or a string, and its value is
  passed to the generated `USING` clause as-is.

  For example, PostgreSQL supports several index types like B-tree (the
  default), Hash, GIN, and GiST. More information on index types can be found
  in the [PostgreSQL docs](http://www.postgresql.org/docs/9.4/static/indexes-types.html).

  ## Partial indexes

  Databases like PostgreSQL and MSSQL support partial indexes.

  A partial index is an index built over a subset of a table. The subset
  is defined by a conditional expression using the `:where` option.
  The `:where` option can be an atom or a string; its value is passed
  to the generated `WHERE` clause as-is.

  More information on partial indexes can be found in the [PostgreSQL
  docs](http://www.postgresql.org/docs/9.4/static/indexes-partial.html).

  ## Examples

      # With no name provided, the name of the below index defaults to
      # products_category_id_sku_index
      create index("products", [:category_id, :sku], unique: true)

      # The name can also be set explicitly
      create index("products", [:category_id, :sku], name: :my_special_name)

      # Indexes can be added concurrently
      create index("products", [:category_id, :sku], concurrently: true)

      # The index type can be specified
      create index("products", [:name], using: :hash)

      # Partial indexes are created by specifying a :where option
      create index("products", [:user_id], where: "price = 0", name: :free_products_index)

      # Covering indexes are created by specifying a :include option
      create index("products", [:user_id], include: [:category_id])

  Indexes also support custom expressions. Some databases may require the
  index expression to be written between parentheses:

      # Create an index on a custom expression
      create index("products", ["(lower(name))"], name: :products_lower_name_index)

      # Create a tsvector GIN index on PostgreSQL
      create index("products", ["(to_tsvector('english', name))"],
                   name: :products_name_vector, using: "GIN")
  """
  def index(table, columns, opts \\ [])

  def index(table, columns, opts) when is_atom(table) do
    index(Atom.to_string(table), columns, opts)
  end

  def index(table, column, opts) when is_binary(table) and is_atom(column) do
    index(table, [column], opts)
  end

  def index(table, columns, opts) when is_binary(table) and is_list(columns) and is_list(opts) do
    validate_index_opts!(opts)
    index = struct(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end

  @doc """
  Shortcut for creating a unique index.

  See `index/3` for more information.
  """
  def unique_index(table, columns, opts \\ [])

  def unique_index(table, columns, opts) when is_list(opts) do
    index(table, columns, [unique: true] ++ opts)
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.map(&to_string(&1))
    |> Enum.map(&String.replace(&1, ~r"[^\w_]", "_"))
    |> Enum.map(&String.replace_trailing(&1, "_", ""))
    |> Enum.join("_")
    |> String.to_atom
  end

  @doc """
  Executes arbitrary SQL, anonymous function or a keyword command.

  The argument is typically a string, containing the SQL command to be executed.
  Keyword commands exist for non-SQL adapters and are not used in most situations.

  Supplying an anonymous function does allow for arbitrary code to execute as
  part of the migration. This is most often used in combination with `repo/0`
  by library authors who want to create high-level migration helpers.

  Reversible commands can be defined by calling `execute/2`.

  ## Examples

      execute "CREATE EXTENSION postgres_fdw"

      execute create: "posts", capped: true, size: 1024

      execute(fn -> repo().query!("SELECT $1::integer + $2", [40, 2], [log: :info]) end)

      execute(fn -> repo().update_all("posts", set: [published: true]) end)
  """
  def execute(command) when is_binary(command) or is_function(command, 0) or is_list(command) do
    Runner.execute command
  end

  @doc """
  Executes reversible SQL commands.

  This is useful for database-specific functionality that does not
  warrant special support in Ecto, for example, creating and dropping
  a PostgreSQL extension. The `execute/2` form avoids having to define
  separate `up/0` and `down/0` blocks that each contain an `execute/1`
  expression.

  The allowed parameters are explained in `execute/1`.

  ## Examples

      defmodule MyApp.MyMigration do
        use Ecto.Migration

        def change do
          execute "CREATE EXTENSION postgres_fdw", "DROP EXTENSION postgres_fdw"
          execute(&execute_up/0, &execute_down/0)
        end

        defp execute_up, do: repo().query!("select 'Up query …';", [], [log: :info])
        defp execute_down, do: repo().query!("select 'Down query …';", [], [log: :info])
      end
  """
  def execute(up, down) when (is_binary(up) or is_function(up, 0) or is_list(up)) and
                             (is_binary(down) or is_function(down, 0) or is_list(down)) do
    Runner.execute %Command{up: up, down: down}
  end

  @doc """
  Gets the migrator direction.
  """
  @spec direction :: :up | :down
  def direction do
    Runner.migrator_direction()
  end

  @doc """
  Gets the migrator repo.
  """
  @spec repo :: Ecto.Repo.t
  def repo do
    Runner.repo()
  end

  @doc """
  Gets the migrator prefix.
  """
  def prefix do
    Runner.prefix()
  end

  @doc """
  Adds a column when creating or altering a table.

  This function also accepts Ecto primitive types as column types
  that are normalized by the database adapter. For example,
  `:string` is converted to `:varchar`, `:binary` to `:bits` or `:blob`,
  and so on.

  However, the column type is not always the same as the type used in your
  schema. For example, a schema that has a `:string` field can be supported by
  columns of type `:char`, `:varchar`, `:text`, and others. For this reason,
  this function also accepts `:text` and other type annotations that are native
  to the database. These are passed to the database as-is.

  To sum up, the column type may be either an Ecto primitive type,
  which is normalized in cases where the database does not understand it,
  such as `:string` or `:binary`, or a database type which is passed as-is.
  Custom Ecto types like `Ecto.UUID` are not supported because
  they are application-level concerns and may not always map to the database.

  ## Examples

      create table("posts") do
        add :title, :string, default: "Untitled"
      end

      alter table("posts") do
        add :summary, :text # Database type
        add :object,  :map  # Elixir type which is handled by the database
      end

  ## Options

    * `:primary_key` - when `true`, marks this field as the primary key.
      If multiple fields are marked, a composite primary key will be created.
    * `:default` - the column's default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.
    * `:null` - when `false`, the column does not allow null values.
    * `:size` - the size of the type (for example, the number of characters).
      The default is no size, except for `:string`, which defaults to `255`.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
    * `:after` - positions field after the specified one. Only supported on MySQL,
      it is ignored by other databases.

  """
  def add(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand {:add, column, type, opts}
  end

  @doc """
  Adds a column if it not exists yet when altering a table.

  If the `type` value is a `%Reference{}`, it is used to add a constraint.

  `type` and `opts` are exactly the same as in `add/3`.

  This command is not reversible as Ecto does not know about column existence before the creation attempt.

  ## Examples

      alter table("posts") do
        add_if_not_exists :title, :string, default: ""
      end

  """
  def add_if_not_exists(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand {:add_if_not_exists, column, type, opts}
  end

  @doc """
  Renames a table.

  ## Examples

      rename table("posts"), to: table("new_posts")
  """
  def rename(%Table{} = table_current, to: %Table{} = table_new) do
    Runner.execute {:rename, __prefix__(table_current), __prefix__(table_new)}
    table_new
  end

  @doc """
  Renames a column outside of the `alter` statement.

  ## Examples

      rename table("posts"), :title, to: :summary
  """
  def rename(%Table{} = table, current_column, to: new_column) when is_atom(current_column) and is_atom(new_column) do
    Runner.execute {:rename, __prefix__(table), current_column, new_column}
    table
  end

  @doc """
  Generates a fragment to be used as a default value.

  ## Examples

      create table("posts") do
        add :inserted_at, :naive_datetime, default: fragment("now()")
      end
  """
  def fragment(expr) when is_binary(expr) do
    {:fragment, expr}
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamp columns.

  Those columns are of `:naive_datetime` type and by default cannot be null. A
  list of `opts` can be given to customize the generated fields.

  ## Options

    * `:inserted_at` - the name of the column for storing insertion times.
      Setting it to `false` disables the column.
    * `:updated_at` - the name of the column for storing last-updated-at times.
      Setting it to `false` disables the column.
    * `:type` - the type of the `:inserted_at` and `:updated_at` columns.
      Defaults to `:naive_datetime`.

  """
  def timestamps(opts \\ []) when is_list(opts) do
    opts = Keyword.merge(Runner.repo_config(:migration_timestamps, []), opts)
    opts = Keyword.put_new(opts, :null, false)

    {type, opts} = Keyword.pop(opts, :type, :naive_datetime)
    {inserted_at, opts} = Keyword.pop(opts, :inserted_at, :inserted_at)
    {updated_at, opts} = Keyword.pop(opts, :updated_at, :updated_at)

    if inserted_at != false, do: add(inserted_at, type, opts)
    if updated_at != false, do: add(updated_at, type, opts)
  end

  @doc """
  Modifies the type of a column when altering a table.

  This command is not reversible unless the `:from` option is provided.
  If the `:from` value is a `%Reference{}`, the adapter will try to drop
  the corresponding foreign key constraints before modifying the type.
  Note `:from` cannot be used to modify primary keys, as those are
  generally trickier to make reversible.

  See `add/3` for more information on supported types.

  ## Examples

      alter table("posts") do
        modify :title, :text
      end

  ## Options

    * `:null` - determines whether the column accepts null values.
    * `:default` - changes the default value of the column.
    * `:from` - specifies the current type of the column.
    * `:size` - specifies the size of the type (for example, the number of characters).
      The default is no size.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
  """
  def modify(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand {:modify, column, type, opts}
  end

  @doc """
  Removes a column when altering a table.

  This command is not reversible as Ecto does not know what type it should add
  the column back as. See `remove/3` as a reversible alternative.

  ## Examples

      alter table("posts") do
        remove :title
      end

  """
  def remove(column) when is_atom(column) do
    Runner.subcommand {:remove, column}
  end

  @doc """
  Removes a column in a reversible way when altering a table.

  `type` and `opts` are exactly the same as in `add/3`, and
  they are used when the command is reversed.

  If the `type` value is a `%Reference{}`, it is used to remove the constraint.

  ## Examples

      alter table("posts") do
        remove :title, :string, default: ""
      end

  """
  def remove(column, type, opts \\ []) when is_atom(column) do
    validate_type!(type)
    Runner.subcommand {:remove, column, type, opts}
  end

  @doc """
  Removes a column only if the column exists when altering the constraint if the reference type is passed
  once it only has the constraint name on reference structure.

  This command is not reversible as Ecto does not know about column existence before the removal attempt.

  ## Examples

      alter table("posts") do
        remove_if_exists :title, :string
      end

  """
  def remove_if_exists(column, type) when is_atom(column) do
    validate_type!(type)
    Runner.subcommand {:remove_if_exists, column, type}
  end

  @doc ~S"""
  Defines a foreign key.

  By default it assumes you are linking to the referenced table
  via its primary key with name `:id`. If you are using a non-default
  key setup (e.g. using `uuid` type keys) you must ensure you set the
  options, such as `:name` and `:type`, to match your target key.

  ## Examples

      create table("products") do
        add :group_id, references("groups")
      end

  ## Options

    * `:name` - The name of the underlying reference, which defaults to
      "#{table}_#{column}_fkey".
    * `:column` - The foreign key column name, which defaults to `:id`.
    * `:prefix` - The prefix for the reference. Defaults to the prefix
      defined by the block's `table/2` struct (the "products" table in
      the example above), or `nil`.
    * `:type` - The foreign key type, which defaults to `:bigserial`.
    * `:on_delete` - What to do if the referenced entry is deleted. May be
      `:nothing` (default), `:delete_all`, `:nilify_all`, or `:restrict`.
    * `:on_update` - What to do if the referenced entry is updated. May be
      `:nothing` (default), `:update_all`, `:nilify_all`, or `:restrict`.
    * `:validate` - Whether or not to validate the foreign key constraint on
       creation or not. Only available in PostgreSQL, and should be followed by
       a command to validate the foreign key in a following migration if false.

  """
  def references(table, opts \\ [])

  def references(table, opts) when is_atom(table) do
    references(Atom.to_string(table), opts)
  end

  def references(table, opts) when is_binary(table) and is_list(opts) do
    opts = Keyword.merge(foreign_key_repo_opts(), opts)
    reference = struct(%Reference{table: table}, opts)

    unless reference.on_delete in [:nothing, :delete_all, :nilify_all, :restrict] do
      raise ArgumentError, "unknown :on_delete value: #{inspect reference.on_delete}"
    end

    unless reference.on_update in [:nothing, :update_all, :nilify_all, :restrict] do
      raise ArgumentError, "unknown :on_update value: #{inspect reference.on_update}"
    end

    reference
  end

  defp foreign_key_repo_opts() do
    case Runner.repo_config(:migration_primary_key, []) do
      false -> []
      opts -> opts
    end
    |> Keyword.take([:type])
    |> Keyword.merge(Runner.repo_config(:migration_foreign_key, []))
  end

  @doc ~S"""
  Defines a constraint (either a check constraint or an exclusion constraint)
  to be evaluated by the database when a row is inserted or updated.

  ## Examples

      create constraint("users", :price_must_be_positive, check: "price > 0")
      create constraint("size_ranges", :no_overlap, exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)
      drop   constraint("products", "price_must_be_positive")

  ## Options

    * `:check` - A check constraint expression. Required when creating a check constraint.
    * `:exclude` - An exclusion constraint expression. Required when creating an exclusion constraint.
    * `:prefix` - The prefix for the table.
    * `:validate` - Whether or not to validate the constraint on creation (true by default). Only
       available in PostgreSQL, and should be followed by a command to validate the foreign key in
       a following migration if false.

  """
  def constraint(table, name, opts \\ [])

  def constraint(table, name, opts) when is_atom(table) do
    constraint(Atom.to_string(table), name, opts)
  end

  def constraint(table, name, opts) when is_binary(table) and is_list(opts) do
    struct(%Constraint{table: table, name: name}, opts)
  end

  @doc "Executes queue migration commands."
  defmacro flush do
    quote do
      if direction() == :down and not function_exported?(__MODULE__, :down, 0) do
        raise "calling flush() inside change when doing rollback is not supported."
      else
        Runner.flush()
      end
    end
  end

  # Validation helpers
  defp validate_type!(:datetime) do
    raise ArgumentError, "the :datetime type in migrations is not supported, " <>
                         "please use :utc_datetime or :naive_datetime instead"
  end

  defp validate_type!(type) when is_atom(type) do
    case Atom.to_string(type) do
      "Elixir." <> _ ->
        raise ArgumentError,
          "#{inspect type} is not a valid database type, " <>
          "please use an atom like :string, :text and so on"
      _ ->
        :ok
    end
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_atom(subtype) do
    validate_type!(subtype)
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_tuple(subtype) do
    for t <- Tuple.to_list(subtype), do: validate_type!(t)
  end

  defp validate_type!(%Reference{} = reference) do
    reference
  end

  defp validate_index_opts!(opts) when is_list(opts) do
    case Keyword.get_values(opts, :where) do
      [_, _ | _] ->
        raise ArgumentError,
              "only one `where` keyword is supported when declaring a partial index. " <>
                "To specify multiple conditions, write a single WHERE clause using AND between them"

      _ ->
        :ok
    end
  end

  defp validate_index_opts!(opts), do: opts

  defp validate_precision_opts!(opts, column) when is_list(opts) do
    if opts[:scale] && !opts[:precision] do
      raise ArgumentError, "column #{Atom.to_string(column)} is missing precision option"
    end
  end

  @doc false
  def __prefix__(%{prefix: prefix} = index_or_table) do
    runner_prefix = Runner.prefix()

    cond do
      is_nil(prefix) ->
        prefix = runner_prefix || Runner.repo_config(:migration_default_prefix, nil)
        %{index_or_table | prefix: prefix}
      is_nil(runner_prefix) or runner_prefix == to_string(prefix) ->
        index_or_table
      true ->
        raise Ecto.MigrationError,  message:
          "the :prefix option `#{prefix}` does match the migrator prefix `#{runner_prefix}`"
    end
  end

  @doc false
  def __primary_key__() do
    case Runner.repo_config(:migration_primary_key, []) do
      false ->
        false

      opts when is_list(opts) ->
        opts = Keyword.put(opts, :primary_key, true)
        {name, opts} = Keyword.pop(opts, :name, :id)
        {type, opts} = Keyword.pop(opts, :type, :bigserial)
        {name, type, opts}
    end
  end
end
