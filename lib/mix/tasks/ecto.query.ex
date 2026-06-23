defmodule Mix.Tasks.Ecto.Query do
  use Mix.Task
  import Inspect.Algebra
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

  The query is evaluated as Elixir code after importing `Ecto.Query`.
  If a local `.iex.exs` file exists, only aliases from the file are made
  available to the query.

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
    query = Code.string_to_quoted!(query, file: "ecto.query")

    code =
      {:__block__, [],
       dot_iex_aliases() ++
         [
           quote(do: import(Ecto.Query)),
           query
         ]}

    {queryable, _binding} = Code.eval_quoted(code, [], file: "ecto.query")

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

  defp dot_iex_aliases do
    with true <- File.regular?(".iex.exs"),
         {:ok, quoted} <- ".iex.exs" |> File.read!() |> Code.string_to_quoted(file: ".iex.exs") do
      collect_aliases(quoted)
    else
      _ -> []
    end
  end

  defp collect_aliases({:__block__, _, expressions}) do
    Enum.filter(expressions, &alias?/1)
  end

  defp collect_aliases(expression) do
    if alias?(expression), do: [expression], else: []
  end

  defp alias?({:alias, _, [aliases]}) do
    aliases?(aliases)
  end

  defp alias?({:alias, _, [aliases, opts]}) when is_list(opts) do
    aliases?(aliases) and alias_opts?(opts)
  end

  defp alias?(_), do: false

  defp aliases?({:__aliases__, _, parts}) do
    Enum.all?(parts, &is_atom/1)
  end

  defp aliases?({{:., _, [prefix, :{}]}, _, aliases}) do
    aliases?(prefix) and Enum.all?(aliases, &aliases?/1)
  end

  defp aliases?(_), do: false

  defp alias_opts?(opts) do
    Keyword.keyword?(opts) and Enum.all?(opts, &alias_opt?/1)
  end

  defp alias_opt?({:as, false}), do: true
  defp alias_opt?({:as, aliases}), do: aliases?(aliases)
  defp alias_opt?({:warn, value}), do: is_boolean(value)
  defp alias_opt?(_), do: false

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

    inspect_fun = fn
      %{__struct__: schema, __meta__: %Ecto.Schema.Metadata{}} = struct, opts ->
        inspect_schema(struct, schema, opts)

      term, opts ->
        previous_fun.(term, opts)
    end

    inspect(entries, limit: :infinity, pretty: true, inspect_fun: inspect_fun)
  end

  defp inspect_schema(struct, schema, opts) do
    drop_fields =
      [:__meta__ | unloaded_associations(schema, struct)] ++ schema.__schema__(:redact_fields)

    infos =
      for %{field: field} = info <- schema.__info__(:struct),
          field not in [:__struct__, :__exception__ | drop_fields],
          do: info

    inspect_map(struct, Macro.inspect_atom(:literal, schema), infos, opts)
  end

  defp inspect_map(map, name, infos, opts) do
    fun = fn %{field: field}, opts -> inspect_keyword({field, Map.get(map, field)}, opts) end
    open = color("%" <> name <> "{", :map, opts)
    sep = color(",", :map, opts)
    close = color("}", :map, opts)

    container_doc(open, infos, close, opts, fun, separator: sep, break: :strict)
  end

  defp inspect_keyword({key, value}, opts) do
    key = color(Macro.inspect_atom(:key, key), :atom, opts)
    concat(key, concat(" ", to_doc(value, opts)))
  end

  defp unloaded_associations(schema, struct) do
    for assoc <- schema.__schema__(:associations),
        match?(%Ecto.Association.NotLoaded{}, Map.get(struct, assoc)) do
      assoc
    end
  end
end
