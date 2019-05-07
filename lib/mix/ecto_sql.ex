defmodule Mix.EctoSQL do
  @moduledoc false

  @doc """
  Ensures the given repository's migrations path exists on the file system.
  """
  @spec ensure_migrations_path(Ecto.Repo.t) :: String.t
  def ensure_migrations_path(repo) do
    path = Path.join(source_repo_priv(repo), "migrations")

    if not Mix.Project.umbrella? and not File.dir?(path) do
      raise_missing_migrations(Path.relative_to_cwd(path), repo)
    end

    path
  end

  defp raise_missing_migrations(path, repo) do
    Mix.raise """
    Could not find migrations directory #{inspect path}
    for repo #{inspect repo}.

    This may be because you are in a new project and the
    migration directory has not been created yet. Creating an
    empty directory at the path above will fix this error.

    If you expected existing migrations to be found, please
    make sure your repository has been properly configured
    and the configured path exists.
    """
  end

  @doc """
  Restarts the app if there was any migration command.
  """
  @spec restart_apps_if_migrated([atom], list()) :: :ok
  def restart_apps_if_migrated(_apps, []), do: :ok
  def restart_apps_if_migrated(apps, [_|_]) do
    # Silence the logger to avoid application down messages.
    Logger.remove_backend(:console)
    for app <- Enum.reverse(apps) do
      Application.stop(app)
    end
    for app <- apps do
      Application.ensure_all_started(app)
    end
    :ok
  after
    Logger.add_backend(:console, flush: true)
  end

  @doc """
  Returns the private repository path relative to the source.
  """
  def source_repo_priv(repo) do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split |> List.last |> Macro.underscore}"
    app = Keyword.fetch!(config, :otp_app)
    Path.join(Mix.Project.deps_paths[app] || File.cwd!, priv)
  end
end
