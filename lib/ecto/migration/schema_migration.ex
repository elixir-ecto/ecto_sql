defmodule Ecto.Migration.SchemaMigration do
  # Defines a schema that works with a table that tracks schema migrations.
  # The table name defaults to `schema_migrations`.
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  @primary_key false
  schema "schema_migrations" do
    field :version, :integer
    timestamps updated_at: false
  end

  # The migration flag is used to signal to the repository
  # we are in a migration operation.
  @default_opts [timeout: :infinity, log: false, schema_migration: true]

  def ensure_schema_migrations_table!(repo, config, opts) do
    {repo, source} = get_repo_and_source(repo, config)
    table_name = String.to_atom(source)
    table = %Ecto.Migration.Table{name: table_name, prefix: opts[:prefix]}
    meta = Ecto.Adapter.lookup_meta(repo.get_dynamic_repo())

    commands = [
      {:add, :version, :bigint, primary_key: true},
      {:add, :inserted_at, :naive_datetime, []}
    ]

    repo.__adapter__().execute_ddl(meta, {:create_if_not_exists, table, commands}, @default_opts)
  end

  def versions(repo, config, prefix) do
    {repo, source} = get_repo_and_source(repo, config)
    {repo, from(m in source, select: type(m.version, :integer)), [prefix: prefix] ++ @default_opts}
  end

  def up(repo, config, version, opts) do
    {repo, source} = get_repo_and_source(repo, config)

    %__MODULE__{version: version}
    |> Ecto.put_meta(source: source)
    |> repo.insert(default_opts(opts))
  end

  def down(repo, config, version, opts) do
    {repo, source} = get_repo_and_source(repo, config)

    from(m in source, where: m.version == type(^version, :integer))
    |> repo.delete_all(default_opts(opts))
  end

  def get_repo_and_source(repo, config) do
    {Keyword.get(config, :migration_repo, repo),
     Keyword.get(config, :migration_source, "schema_migrations")}
  end

  defp default_opts(opts) do
    Keyword.merge(
      @default_opts,
      [prefix: opts[:prefix], log: Keyword.get(opts, :log_migrator_sql, false)]
    )
  end
end
