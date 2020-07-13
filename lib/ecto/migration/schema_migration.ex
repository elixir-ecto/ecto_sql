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
    {repo, source} = get_repo_and_source(repo)
    table_name = String.to_atom(source)
    table = %Ecto.Migration.Table{name: table_name, prefix: opts[:prefix]}
    meta = Ecto.Adapter.lookup_meta(repo.get_dynamic_repo())

    commands = [
      {:add, :version, :bigint, primary_key: true},
      {:add, :inserted_at, :naive_datetime, []}
    ]

    # DDL queries do not log, so we do not need to pass log: false here.
    repo.__adapter__().execute_ddl(meta, {:create_if_not_exists, table, commands}, @opts)
  end

  def versions(repo, prefix) do
    {_repo, source} = get_repo_and_source(repo)

    from(m in source, select: type(m.version, :integer))
    |> Map.put(:prefix, prefix)
  end

  def up(repo, version, prefix) do
    {repo, source} = get_repo_and_source(repo)

    %__MODULE__{version: version}
    |> Ecto.put_meta(source: source)
    |> repo.insert([prefix: prefix] ++ @opts)
  end

  def down(repo, version, prefix) do
    {repo, source} = get_repo_and_source(repo)

    from(m in source, where: m.version == type(^version, :integer))
    |> repo.delete_all([prefix: prefix] ++ @opts)
  end

  defp get_repo_and_source(repo) do
    config = repo.config()

    {Keyword.get(config, :migration_repo, repo),
     Keyword.get(config, :migration_source, "schema_migrations")}
  end
end
