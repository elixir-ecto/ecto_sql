defmodule Mix.Tasks.Ecto.Query do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Runs a query against the repository"

  @switches [
    limit: :integer,
    repo: [:string, :keep],
    sql: :boolean,
    no_compile: :boolean,
    no_deps_check: :boolean
  ]

  @aliases [
    r: :repo
  ]

  @moduledoc """
  Runs the given query against the repository.

  The query is evaluated as Elixir code after loading the current
  `.iex.exs` file, if one exists, and importing `Ecto.Query`.

  The query runs inside a read-only transaction.

  ## Examples

      $ mix ecto.query "from p in Post, where: p.published"
      $ mix ecto.query -r Custom.Repo "from p in Post, limit: 10"
      $ mix ecto.query --sql "from p in Post, where: p.published"

  ## Command line options

    * `-r`, `--repo` - the repo to query
    * `--limit` - limits the number of printed entries. Defaults to 100.
    * `--sql` - prints the generated SQL and parameters instead of running the query

  """

  @default_limit 100

  @impl true
  def run(args) do
    repos = parse_repo(args)
    {opts, query_args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repo =
      case repos do
        [repo] ->
          repo

        [] ->
          Mix.raise("ecto.query expects a repository to be configured or given as -r MyApp.Repo")

        [_ | _] ->
          Mix.raise("ecto.query found multiple repositories, please pass one with -r")
      end

    query =
      case query_args do
        [query] -> query
        [] -> Mix.raise("ecto.query expects a query to be given")
        [_ | _] -> Mix.raise("ecto.query expects a single query to be given")
      end

    limit = Keyword.get(opts, :limit, @default_limit)

    if limit < 0 do
      Mix.raise("ecto.query expects --limit to be greater than or equal to zero")
    end

    Mix.Task.run("app.start", args)
    ensure_repo(repo, args)

    query = eval_query(query)

    result =
      if opts[:sql] do
        {:ok, format_sql(repo, query)}
      else
        read_only_transaction(repo, fn ->
          query
          |> repo.all()
          |> Enum.take(limit)
          |> inspect_entries()
        end)
      end

    result
    |> case do
      {:ok, output} ->
        Mix.shell().info(output)

      {:error, reason} ->
        Mix.raise("ecto.query failed: #{inspect(reason)}")
    end
  end

  defp eval_query(query) do
    code = [dot_iex(), "\nimport Ecto.Query\n", query]

    {queryable, _binding} =
      code
      |> IO.iodata_to_binary()
      |> Code.eval_string([], file: "ecto.query")

    to_query!(queryable)
  end

  defp to_query!(queryable) do
    Ecto.Queryable.to_query(queryable)
  rescue
    Protocol.UndefinedError ->
      Mix.raise(
        "Expected ecto.query to evaluate to a queryable expression, got: #{inspect(queryable)}"
      )
  end

  defp dot_iex do
    if File.regular?(".iex.exs") do
      [File.read!(".iex.exs"), "\n"]
    else
      []
    end
  end

  defp read_only_transaction(repo, fun) do
    do_read_only_transaction(repo.__adapter__(), repo, fun)
  end

  defp do_read_only_transaction(Ecto.Adapters.Postgres, repo, fun) do
    repo.transaction(fn ->
      repo.query!("SET TRANSACTION READ ONLY", [], log: false)
      fun.()
    end)
  end

  defp do_read_only_transaction(Ecto.Adapters.MyXQL, repo, fun) do
    repo.checkout(fn ->
      repo.query!("START TRANSACTION READ ONLY", [], log: false)

      try do
        {:ok, fun.()}
      after
        repo.query!("ROLLBACK", [], log: false)
      end
    end)
  end

  defp do_read_only_transaction(adapter, _repo, _fun) do
    Mix.raise(
      "ecto.query requires read-only transactions, which are not supported by #{inspect(adapter)}"
    )
  end

  defp format_sql(repo, query) do
    {sql, params} = repo.to_sql(:all, query)

    """
    SQL:
    #{sql}

    Params:
    #{inspect(params, limit: :infinity, pretty: true)}
    """
  end

  defp inspect_entries(entries) do
    previous_fun = Inspect.Opts.default_inspect_fun()

    Inspect.Opts.default_inspect_fun(fn
      %{__struct__: schema, __meta__: %Ecto.Schema.Metadata{}} = struct, opts ->
        inspect_schema(struct, schema, opts)

      term, opts ->
        previous_fun.(term, opts)
    end)

    try do
      inspect(entries, limit: :infinity, pretty: true)
    after
      Inspect.Opts.default_inspect_fun(previous_fun)
    end
  end

  defp inspect_schema(struct, schema, opts) do
    drop_fields =
      [:__meta__ | unloaded_associations(schema, struct)] ++ schema.__schema__(:redact_fields)

    infos =
      for %{field: field} = info <- schema.__info__(:struct),
          field not in [:__struct__, :__exception__ | drop_fields],
          do: info

    Inspect.Map.inspect(struct, Macro.inspect_atom(:literal, schema), infos, opts)
  end

  defp unloaded_associations(schema, struct) do
    for assoc <- schema.__schema__(:associations),
        match?(%Ecto.Association.NotLoaded{}, Map.get(struct, assoc)) do
      assoc
    end
  end
end
