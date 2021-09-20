defmodule Mix.Tasks.Ecto.Rollback do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Rolls back the repository migrations"

  @aliases [
    r: :repo,
    n: :step
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
    repo: [:keep, :string],
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :keep
  ]

  @moduledoc """
  Reverts applied migrations in the given repository.

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

  This task rolls back the last applied migration by default. To roll
  back to a version number, supply `--to version_number`. To roll
  back a specific number of times, use `--step n`. To undo all applied
  migrations, provide `--all`.

  The repositories to rollback are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      $ mix ecto.rollback
      $ mix ecto.rollback -r Custom.Repo

      $ mix ecto.rollback -n 3
      $ mix ecto.rollback --step 3

      $ mix ecto.rollback --to 20080906120000

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

    * `--step`, `-n` - revert n migrations

    * `--strict-version-order` - abort when applying a migration with old
      timestamp (otherwise it emits a warning)

    * `--to` - revert all migrations down to and including version

  """

  @impl true
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    repos = parse_repo(args)
    {opts, _} = OptionParser.parse! args, strict: @switches, aliases: @aliases

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :step, 1)

    Mix.Tasks.Ecto.Migrate.validate_log_sql_mode!(opts)

    opts = Mix.Tasks.Ecto.Migrate.conform_log_options(opts)

    # Start ecto_sql explicitly before as we don't need
    # to restart those apps if migrated.
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    for repo <- repos do
      ensure_repo(repo, args)
      paths = ensure_migrations_paths(repo, opts)
      pool = repo.config[:pool]

      fun =
        if Code.ensure_loaded?(pool) and function_exported?(pool, :unboxed_run, 2) do
          &pool.unboxed_run(&1, fn -> migrator.(&1, paths, :down, opts) end)
        else
          &migrator.(&1, paths, :down, opts)
        end

      case Ecto.Migrator.with_repo(repo, fun, [mode: :temporary] ++ opts) do
        {:ok, _migrated, _apps} -> :ok
        {:error, error} -> Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
      end
    end

    :ok
  end
end
