defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Runs the repository migrations"

  @aliases [
    n: :step,
    r: :repo
  ]

  @switches [
    all: :boolean,
    step: :integer,
    to: :integer,
    quiet: :boolean,
    prefix: :string,
    pool_size: :integer,
    log_sql: :boolean,
    log_sql_mode: :string,
    strict_version_order: :boolean,
    repo: [:keep, :string],
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :keep
  ]

  @moduledoc """
  Runs the pending migrations for the given repository.

  Migrations are expected at "priv/YOUR_REPO/migrations" directory
  of the current application, where "YOUR_REPO" is the last segment
  in your repository name. For example, the repository `MyApp.Repo`
  will use "priv/repo/migrations". The repository `Whatever.MyRepo`
  will use "priv/my_repo/migrations".

  You can configure a repository to use another directory by specifying
  the `:priv` key under the repository configuration. The "migrations"
  part will be automatically appended to it. For instance, to use
  "priv/custom_repo/migrations":

      config :my_app, MyApp.Repo, priv: "priv/custom_repo"

  This task runs all pending migrations by default. To migrate up to a
  specific version number, supply `--to version_number`. To migrate a
  specific number of times, use `--step n`.

  The repositories to migrate are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since Ecto tasks can only be executed once, if you need to migrate
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      $ mix ecto.migrate
      $ mix ecto.migrate -r Custom.Repo

      $ mix ecto.migrate -n 3
      $ mix ecto.migrate --step 3

      $ mix ecto.migrate --to 20080906120000

  ## Command line options

    * `--all` - run all pending migrations

    * `--log-sql` - log the underlying sql statements for migrations

    * `--log-sql-mode` - how much SQL to log. `"commands"` logs only the SQL
      from commands in the migrations. `"all"` will log all SQL. Defaults to `"commands"`.

    * `--migrations-path` - the path to load the migrations from, defaults to
      `"priv/repo/migrations"`. This option may be given multiple times in which
      case the migrations are loaded from all the given directories and sorted
      as if they were in the same one

    * `--no-compile` - does not compile applications before migrating

    * `--no-deps-check` - does not check dependencies before migrating

    * `--pool-size` - the pool size if the repository is started
      only for the task (defaults to 2)

    * `--prefix` - the prefix to run migrations on

    * `--quiet` - do not log migration commands

    * `-r`, `--repo` - the repo to migrate

    * `--step`, `-n` - run n number of pending migrations

    * `--strict-version-order` - abort when applying a migration with old
      timestamp (otherwise it emits a warning)

    * `--to` - run all migrations up to and including version

  """

  @impl true
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    repos = parse_repo(args)
    {opts, _} = OptionParser.parse! args, strict: @switches, aliases: @aliases

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :all, true)

    validate_log_sql_mode!(opts)

    opts = conform_log_options(opts)

    # Start ecto_sql explicitly before as we don't need
    # to restart those apps if migrated.
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    for repo <- repos do
      ensure_repo(repo, args)
      paths = ensure_migrations_paths(repo, opts)
      pool = repo.config[:pool]

      fun =
        if Code.ensure_loaded?(pool) and function_exported?(pool, :unboxed_run, 2) do
          &pool.unboxed_run(&1, fn -> migrator.(&1, paths, :up, opts) end)
        else
          &migrator.(&1, paths, :up, opts)
        end

      case Ecto.Migrator.with_repo(repo, fun, [mode: :temporary] ++ opts) do
        {:ok, _migrated, _apps} -> :ok
        {:error, error} -> Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
      end
    end

    :ok
  end

  def validate_log_sql_mode!(opts) do
    case Keyword.get(opts, :log_sql_mode) do
      nil -> :ok
      "commands" -> :ok
      "all" -> :ok
      mode ->
        Mix.raise("""
        #{inspect(mode)} is not a valid log_sql_mode.
        Valid options are: "all", "commands"
        """)
    end
  end

  def conform_log_options(opts) do
    opts =
      if opts[:log_sql_mode] == "all",
        do: Keyword.merge(opts, [log_sql: :info, log: :info, log_all: true]),
        else: opts

    opts =
      if opts[:log_sql_mode] == "commands",
        do: Keyword.merge(opts, [log_sql: :info, log: :info, log_all: false]),
        else: opts

    if opts[:quiet],
      do: Keyword.merge(opts, [log: false, log_sql: false, log_all: false]),
      else: opts
  end
end
