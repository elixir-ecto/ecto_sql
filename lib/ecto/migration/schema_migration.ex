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

  @opts [timeout: :infinity, log: false]

  def ensure_schema_migrations_table!(repo, opts) do
    table_name = repo |> get_source |> String.to_atom()
    table = %Ecto.Migration.Table{name: table_name, prefix: opts[:prefix]}
    repo_name = Keyword.get(opts, :repo_name, repo)
    meta = Ecto.Adapter.lookup_meta(repo_name)

    commands = [
      {:add, :version, :bigint, primary_key: true},
      {:add, :inserted_at, :naive_datetime, []}
    ]

    # DDL queries do not log, so we do not need to pass log: false here.
    repo.__adapter__.execute_ddl(meta, {:create_if_not_exists, table, commands}, @opts)
  end

  def versions(repo, prefix) do
    from(p in get_source(repo), select: type(p.version, :integer))
    |> Map.put(:prefix, prefix)
  end

  def up(repo, repo_name, version, prefix) do
    %__MODULE__{version: version}
    |> Ecto.put_meta(prefix: prefix, source: get_source(repo))
    |> repo_insert(repo_name)
  end

  def down(repo, repo_name, version, prefix) do
    from(p in get_source(repo), where: p.version == type(^version, :integer))
    |> Map.put(:prefix, prefix)
    |> repo_delete_all(repo_name)
  end

  def get_source(repo) do
    Keyword.get(repo.config, :migration_source, "schema_migrations")
  end

  defp repo_insert(schema_migration_struct, repo_name) do
    Ecto.Repo.Schema.insert!(repo_name, schema_migration_struct, @opts)
  end

  defp repo_delete_all(schema_migration_query, repo_name) do
    Ecto.Repo.Queryable.delete_all(repo_name, schema_migration_query, @opts)
  end
end
