defmodule Ecto.Migration.BootMigrator do
  @moduledoc """
  A process you can add to your Application Supervisor to run migrations. This will attempt to run migrations, and then silently shut its self down.

  Add the following to the top of your application children spec:
     {Ecto.Migration.BootMigrator, otp_app: :my_app}

  Optionally pass `:skip` to skip them. 

  #TODO More config
  """
  use GenServer

  # Callbacks
  @impl true
  def init(opts) do
    app = Keyword.fetch!(opts, :otp_app)
    repos = Application.fetch_env!(app, :ecto_repos)

    # TODO probably a better way
    skip? = Keyword.get(opts, :skip, System.get_env("SKIP_MIGRATIONS") || false)
    migrator = Keyword.get(opts, :migrator, &Ecto.Migrator.run/3)

    unless skip? do
      for repo <- repos do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &migrator.(&1, :up, all: true))
      end
    end

    :ignore
  end
end
