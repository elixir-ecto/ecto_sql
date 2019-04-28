defmodule Mix.Tasks.Ecto.Load do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Loads previously dumped database structure"
  @default_opts [force: false, quiet: false]

  @aliases [
    d: :dump_path,
    f: :force,
    q: :quiet,
    r: :repo
  ]

  @switches [
    dump_path: :string,
    force: :boolean,
    quiet: :boolean,
    repo: [:string, :keep],
    no_compile: :boolean,
    no_deps_check: :boolean,
    skip_if_loaded: :boolean
  ]

  @moduledoc """
  Loads the current environment's database structure for the
  given repository from a previously dumped structure file.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  This task needs some shell utility to be present on the machine
  running the task.

   Database   | Utility needed
   :--------- | :-------------
   PostgreSQL | psql
   MySQL      | mysql

  ## Example

      mix ecto.load

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into
    * `-d`, `--dump-path` - the path of the dump file to load from
    * `-q`, `--quiet` - run the command quietly
    * `-f`, `--force` - do not ask for confirmation when loading data.
      Configuration is asked only when `:start_permanent` is set to true
      (typically in production)
    * `--no-compile` - does not compile applications before loading
    * `--no-deps-check` - does not check depedendencies before loading
    * `--skip-if-loaded` - does not load the dump file if the repo has any
      migration up

  """

  @impl true
  def run(args, migrations \\ &Ecto.Migrator.migrations/2) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(parse_repo(args), fn repo ->
      ensure_repo(repo, args)

      ensure_implements(
        repo.__adapter__,
        Ecto.Adapter.Structure,
        "load structure for #{inspect(repo)}"
      )

      path = ensure_migrations_path(repo)
      {:ok, pid, _} = ensure_started(repo, all: true)
      repo_status = migrations.(repo, path)
      pid && repo.stop()

      loaded? = loaded?(repo_status)

      cond do
        loaded? and opts[:skip_if_loaded] ->
          Mix.shell().info("Skipped since a structure for #{inspect(repo)} has been loaded")

        (skip_safety_warnings?() and !loaded?) or opts[:force] or confirm_load(repo) ->
          load_structure(repo, opts)
      end
    end)
  end

  def loaded?(repo_status) do
    Enum.any?(repo_status, fn {status, _, _} -> status == :up end)
  end

  defp skip_safety_warnings? do
    Mix.Project.config()[:start_permanent] != true
  end

  defp confirm_load(repo) do
    Mix.shell().yes?(
      "Are you sure you want to load a new structure for #{inspect(repo)}? Any existing data in this repo may be lost."
    )
  end

  defp load_structure(repo, opts) do
    config = Keyword.merge(repo.config, opts)

    case repo.__adapter__.structure_load(source_repo_priv(repo), config) do
      {:ok, location} ->
        unless opts[:quiet] do
          Mix.shell.info "The structure for #{inspect repo} has been loaded from #{location}"
        end
      {:error, term} when is_binary(term) ->
        Mix.raise "The structure for #{inspect repo} couldn't be loaded: #{term}"
      {:error, term} ->
        Mix.raise "The structure for #{inspect repo} couldn't be loaded: #{inspect term}"
    end
  end
end
