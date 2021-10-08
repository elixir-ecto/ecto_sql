defmodule Ecto.Adapters.SQL do
  @moduledoc """
  This application provides functionality for working with
  SQL databases in `Ecto`.

  ## Built-in adapters

  By default, we support the following adapters:

    * `Ecto.Adapters.Postgres` for Postgres
    * `Ecto.Adapters.MyXQL` for MySQL
    * `Ecto.Adapters.Tds` for SQLServer

  ## Migrations

  Ecto supports database migrations. You can generate a migration
  with:

      $ mix ecto.gen.migration create_posts

  This will create a new file inside `priv/repo/migrations` with the
  `change` function. Check `Ecto.Migration` for more information.

  To interface with migrations, developers typically use mix tasks:

    * `mix ecto.migrations` - lists all available migrations and their status
    * `mix ecto.migrate` - runs a migration
    * `mix ecto.rollback` - rolls back a previously run migration

  If you want to run migrations programmatically, see `Ecto.Migrator`.

  ## SQL sandbox

  `ecto_sql` provides a sandbox for testing. The sandbox wraps each
  test in a transaction, making sure the tests are isolated and can
  run concurrently. See `Ecto.Adapters.SQL.Sandbox` for more information.

  ## Structure load and dumping

  If you have an existing database, you may want to dump its existing
  structure and make it reproducible from within Ecto. This can be
  achieved with two Mix tasks:

    * `mix ecto.load` - loads an existing structure into the database
    * `mix ecto.dump` - dumps the existing database structure to the filesystem

  For creating and dropping databases, see `mix ecto.create`
  and `mix ecto.drop` that are included as part of Ecto.

  ## Custom adapters

  Developers can implement their own SQL adapters by using
  `Ecto.Adapters.SQL` and by implementing the callbacks required
  by `Ecto.Adapters.SQL.Connection`  for handling connections and
  performing queries. The connection handling and pooling for SQL
  adapters should be built using the `DBConnection` library.

  When using `Ecto.Adapters.SQL`, the following options are required:

    * `:driver` (required) - the database driver library.
      For example: `:postgrex`

  """

  require Logger

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Ecto.Adapter
      @behaviour Ecto.Adapter.Migration
      @behaviour Ecto.Adapter.Queryable
      @behaviour Ecto.Adapter.Schema
      @behaviour Ecto.Adapter.Transaction

      opts = unquote(opts)
      @conn __MODULE__.Connection
      @driver Keyword.fetch!(opts, :driver)

      @impl true
      defmacro __before_compile__(env) do
        Ecto.Adapters.SQL.__before_compile__(@driver, env)
      end

      @impl true
      def ensure_all_started(config, type) do
        Ecto.Adapters.SQL.ensure_all_started(@driver, config, type)
      end

      @impl true
      def init(config) do
        Ecto.Adapters.SQL.init(@conn, @driver, config)
      end

      @impl true
      def checkout(meta, opts, fun) do
        Ecto.Adapters.SQL.checkout(meta, opts, fun)
      end

      @impl true
      def checked_out?(meta) do
        Ecto.Adapters.SQL.checked_out?(meta)
      end

      @impl true
      def loaders({:map, _}, type),   do: [&Ecto.Type.embedded_load(type, &1, :json)]
      def loaders(:binary_id, type),  do: [Ecto.UUID, type]
      def loaders(_, type),           do: [type]

      @impl true
      def dumpers({:map, _}, type),   do: [&Ecto.Type.embedded_dump(type, &1, :json)]
      def dumpers(:binary_id, type),  do: [type, Ecto.UUID]
      def dumpers(_, type),           do: [type]

      ## Query

      @impl true
      def prepare(:all, query) do
        {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.all(query))}}
      end

      def prepare(:update_all, query) do
        {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.update_all(query))}}
      end

      def prepare(:delete_all, query) do
        {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.delete_all(query))}}
      end

      @impl true
      def execute(adapter_meta, query_meta, query, params, opts) do
        Ecto.Adapters.SQL.execute(adapter_meta, query_meta, query, params, opts)
      end

      @impl true
      def stream(adapter_meta, query_meta, query, params, opts) do
        Ecto.Adapters.SQL.stream(adapter_meta, query_meta, query, params, opts)
      end

      ## Schema

      @impl true
      def autogenerate(:id),        do: nil
      def autogenerate(:embed_id),  do: Ecto.UUID.generate()
      def autogenerate(:binary_id), do: Ecto.UUID.bingenerate()

      @impl true
      def insert_all(adapter_meta, schema_meta, header, rows, on_conflict, returning, placeholders, opts) do
        Ecto.Adapters.SQL.insert_all(adapter_meta, schema_meta, @conn, header, rows, on_conflict, returning, placeholders, opts)
      end

      @impl true
      def insert(adapter_meta, %{source: source, prefix: prefix}, params,
                 {kind, conflict_params, _} = on_conflict, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(prefix, source, fields, [fields], on_conflict, returning, [])
        Ecto.Adapters.SQL.struct(adapter_meta, @conn, sql, :insert, source, [], values ++ conflict_params, kind, returning, opts)
      end

      @impl true
      def update(adapter_meta, %{source: source, prefix: prefix}, fields, params, returning, opts) do
        {fields, field_values} = :lists.unzip(fields)
        filter_values = params |> Keyword.values() |> Enum.reject(&is_nil(&1))
        sql = @conn.update(prefix, source, fields, params, returning)
        Ecto.Adapters.SQL.struct(adapter_meta, @conn, sql, :update, source, params, field_values ++ filter_values, :raise, returning, opts)
      end

      @impl true
      def delete(adapter_meta, %{source: source, prefix: prefix}, params, opts) do
        filter_values = params |> Keyword.values() |> Enum.reject(&is_nil(&1))
        sql = @conn.delete(prefix, source, params, [])
        Ecto.Adapters.SQL.struct(adapter_meta, @conn, sql, :delete, source, params, filter_values, :raise, [], opts)
      end

      ## Transaction

      @impl true
      def transaction(meta, opts, fun) do
        Ecto.Adapters.SQL.transaction(meta, opts, fun)
      end

      @impl true
      def in_transaction?(meta) do
        Ecto.Adapters.SQL.in_transaction?(meta)
      end

      @impl true
      def rollback(meta, value) do
        Ecto.Adapters.SQL.rollback(meta, value)
      end

      ## Migration

      @impl true
      def execute_ddl(meta, definition, opts) do
        Ecto.Adapters.SQL.execute_ddl(meta, @conn, definition, opts)
      end

      defoverridable [prepare: 2, execute: 5, insert: 6, update: 6, delete: 4, insert_all: 8,
                      execute_ddl: 3, loaders: 2, dumpers: 2, autogenerate: 1,
                      ensure_all_started: 2, __before_compile__: 1]
    end
  end

  @doc """
  Converts the given query to SQL according to its kind and the
  adapter in the given repository.

  ## Examples

  The examples below are meant for reference. Each adapter will
  return a different result:

      iex> Ecto.Adapters.SQL.to_sql(:all, Repo, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

      iex> Ecto.Adapters.SQL.to_sql(:update_all, Repo,
                                    from(p in Post, update: [set: [title: ^"hello"]]))
      {"UPDATE posts AS p SET title = $1", ["hello"]}

  This function is also available under the repository with name `to_sql`:

      iex> Repo.to_sql(:all, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

  """
  @spec to_sql(:all | :update_all | :delete_all, Ecto.Repo.t, Ecto.Queryable.t) ::
               {String.t, [term]}
  def to_sql(kind, repo, queryable) do
    case Ecto.Adapter.Queryable.prepare_query(kind, repo, queryable) do
      {{:cached, _update, _reset, {_id, cached}}, params} ->
        {String.Chars.to_string(cached), params}

      {{:cache, _update, {_id, prepared}}, params} ->
        {prepared, params}

      {{:nocache, {_id, prepared}}, params} ->
        {prepared, params}
    end
  end

  @doc """
  Executes an EXPLAIN statement or similar for the given query according to its kind and the
  adapter in the given repository.

  ## Examples

      # Postgres
      iex> Ecto.Adapters.SQL.explain(Repo, :all, Post)
      "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)"

      # MySQL
      iex> Ecto.Adapters.SQL.explain(Repo, :all, from(p in Post, where: p.title == "title")) |> IO.puts()
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
      | id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
      |  1 | SIMPLE      | p0    | NULL       | ALL  | NULL          | NULL | NULL    | NULL |    1 |    100.0 | Using where |
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+

      # Shared opts
      iex> Ecto.Adapters.SQL.explain(Repo, :all, Post, analyze: true, timeout: 20_000)
      "Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=443) (actual time=0.013..0.013 rows=0 loops=1)\\nPlanning Time: 0.031 ms\\nExecution Time: 0.021 ms"

  It's safe to execute it for updates and deletes, no data change will be committed:

      iex> Ecto.Adapters.SQL.explain(Repo, :update_all, from(p in Post, update: [set: [title: "new title"]]))
      "Update on posts p0  (cost=0.00..11.70 rows=170 width=449)\\n  ->  Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=449)"

  This function is also available under the repository with name `explain`:

      iex> Repo.explain(:all, from(p in Post, where: p.title == "title"))
      "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)\\n  Filter: ((title)::text = 'title'::text)"

  ### Options

  Built-in adapters support passing `opts` to the EXPLAIN statement according to the following:

  Adapter          | Supported opts
  ---------------- | --------------
  Postgrex         | `analyze`, `verbose`, `costs`, `settings`, `buffers`, `timing`, `summary`
  MyXQL            | None

  _Postgrex_: Check [PostgreSQL doc](https://www.postgresql.org/docs/current/sql-explain.html) for version compatibility.

  _MyXQL_: `EXTENDED` and `PARTITIONS` opts were [deprecated](https://dev.mysql.com/doc/refman/5.7/en/explain.html) and are enabled by default.

  Also note that:

    * Currently `:map`, `:yaml`, and `:text` format options are supported
      for PostgreSQL. `:map` is the deserialized JSON encoding. The last two
      options return the result as a string.
    * Any other value passed to `opts` will be forwarded to the underlying
      adapter query function, including Repo shared options such as `:timeout`;
    * Non built-in adapters may have specific behavior and you should consult
      their own documentation.

  """
  @spec explain(pid() | Ecto.Repo.t | Ecto.Adapter.adapter_meta,
                :all | :update_all | :delete_all,
                Ecto.Queryable.t, opts :: Keyword.t) :: String.t | Exception.t
  def explain(repo, operation, queryable, opts \\ [])

  def explain(repo, operation, queryable, opts) when is_atom(repo) or is_pid(repo) do
    explain(Ecto.Adapter.lookup_meta(repo), operation, queryable, opts)
  end

  def explain(%{repo: repo} = adapter_meta, operation, queryable, opts) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:explain, fn _, _ ->
      {prepared, prepared_params} = to_sql(operation, repo, queryable)
      sql_call(adapter_meta, :explain_query, [prepared], prepared_params, opts)
    end)
     |> Ecto.Multi.run(:rollback, fn _, _ ->
       {:error, :forced_rollback}
     end)
     |> repo.transaction()
     |> case do
       {:error, :rollback, :forced_rollback, %{explain: result}} -> result
       {:error, :explain, error, _} -> raise error
       _ -> raise "unable to execute explain"
     end
  end

  @doc """
  Returns a stream that runs a custom SQL query on given repo when reduced.

  In case of success it is a enumerable containing maps with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  In case of failure it raises an exception.

  If the adapter supports a collectable stream, the stream may also be used as
  the collectable in `Enum.into/3`. Behaviour depends on the adapter.

  ## Options

    * `:log` - When false, does not log the query
    * `:max_rows` - The number of rows to load from the database as we stream

  ## Examples

      iex> Ecto.Adapters.SQL.stream(MyRepo, "SELECT $1::integer + $2", [40, 2]) |> Enum.to_list()
      [%{rows: [[42]], num_rows: 1}]

  """
  @spec stream(Ecto.Repo.t, String.t, [term], Keyword.t) :: Enum.t
  def stream(repo, sql, params \\ [], opts \\ []) do
    repo
    |> Ecto.Adapter.lookup_meta()
    |> Ecto.Adapters.SQL.Stream.build(sql, params, opts)
  end

  @doc """
  Same as `query/4` but raises on invalid queries.
  """
  @spec query!(Ecto.Repo.t | Ecto.Adapter.adapter_meta, iodata, [term], Keyword.t) ::
               %{:rows => nil | [[term] | binary],
                 :num_rows => non_neg_integer,
                 optional(atom) => any}
  def query!(repo, sql, params \\ [], opts \\ []) do
    case query(repo, sql, params, opts) do
      {:ok, result} -> result
      {:error, err} -> raise_sql_call_error err
    end
  end

  @doc """
  Runs custom SQL query on given repo.

  In case of success, it must return an `:ok` tuple containing
  a map with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  ## Options

    * `:log` - When false, does not log the query

  ## Examples

      iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [[42]], num_rows: 1}}

  For convenience, this function is also available under the repository:

      iex> MyRepo.query("SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [[42]], num_rows: 1}}

  """
  @spec query(pid() | Ecto.Repo.t | Ecto.Adapter.adapter_meta, iodata, [term], Keyword.t) ::
              {:ok, %{:rows => nil | [[term] | binary],
                      :num_rows => non_neg_integer,
                      optional(atom) => any}}
              | {:error, Exception.t}
  def query(repo, sql, params \\ [], opts \\ [])

  def query(repo, sql, params, opts) when is_atom(repo) or is_pid(repo) do
    query(Ecto.Adapter.lookup_meta(repo), sql, params, opts)
  end

  def query(adapter_meta, sql, params, opts) do
    sql_call(adapter_meta, :query, [sql], params, opts)
  end

  defp sql_call(adapter_meta, callback, args, params, opts) do
    %{pid: pool, telemetry: telemetry, sql: sql, opts: default_opts} = adapter_meta
    conn = get_conn_or_pool(pool)
    opts = with_log(telemetry, params, opts ++ default_opts)
    args = args ++ [params, opts]
    apply(sql, callback, [conn | args])
  end

  defp put_source(opts, %{sources: sources}) when is_binary(elem(elem(sources, 0), 0)) do
    {source, _, _} = elem(sources, 0)
    Keyword.put(opts, :source, source)
  end

  defp put_source(opts, _) do
    opts
  end

  @doc """
  Check if the given `table` exists.

  Returns `true` if the `table` exists in the `repo`, otherwise `false`.
  The table is checked against the current database/schema in the connection.
  """
  @spec table_exists?(Ecto.Repo.t, table :: String.t) :: boolean
  def table_exists?(repo, table) when is_atom(repo) do
    %{sql: sql} = adapter_meta = Ecto.Adapter.lookup_meta(repo)
    {query, params} = sql.table_exists_query(table)
    query!(adapter_meta, query, params, []).num_rows != 0
  end

  # Returns a formatted table for a given query `result`.
  #
  # ## Examples
  #
  #     iex> Ecto.Adapters.SQL.format_table(query) |> IO.puts()
  #     +---------------+---------+--------+
  #     | title         | counter | public |
  #     +---------------+---------+--------+
  #     | My Post Title |       1 | NULL   |
  #     +---------------+---------+--------+
  @doc false
  @spec format_table(%{:columns => [String.t] | nil, :rows => [term()] | nil, optional(atom) => any()}) :: String.t
  def format_table(result)

  def format_table(nil), do: ""
  def format_table(%{columns: nil}), do: ""
  def format_table(%{columns: []}), do: ""
  def format_table(%{columns: columns, rows: nil}), do: format_table(%{columns: columns, rows: []})

  def format_table(%{columns: columns, rows: rows}) do
    column_widths =
      [columns | rows]
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn column_with_rows ->
        column_with_rows |> Enum.map(&binary_length/1) |> Enum.max()
      end)

    [
      separator(column_widths),
      "\n",
      cells(columns, column_widths),
      "\n",
      separator(column_widths),
      "\n",
      Enum.map(rows, &cells(&1, column_widths) ++ ["\n"]),
      separator(column_widths)
    ]
    |> IO.iodata_to_binary()
  end


  defp binary_length(nil), do: 4 # NULL
  defp binary_length(binary) when is_binary(binary), do: String.length(binary)
  defp binary_length(other), do: other |> inspect() |> String.length()

  defp separator(widths) do
    Enum.map(widths, & [?+, ?-, String.duplicate("-", &1), ?-]) ++ [?+]
  end

  defp cells(items, widths) do
    cell =
      [items, widths]
      |> List.zip()
      |> Enum.map(fn {item, width} -> [?|, " ", format_item(item, width) , " "] end)

    [cell | [?|]]
  end

  defp format_item(nil, width), do: String.pad_trailing("NULL", width)
  defp format_item(item, width) when is_binary(item), do: String.pad_trailing(item, width)
  defp format_item(item, width) when is_number(item), do: item |> inspect() |> String.pad_leading(width)
  defp format_item(item, width), do: item |> inspect() |> String.pad_trailing(width)

  ## Callbacks

  @doc false
  def __before_compile__(driver, _env) do
    case Application.get_env(:ecto, :json_library) do
      nil ->
        :ok

      Jason ->
        IO.warn """
        Jason is the default :json_library in Ecto 3.0.
        You no longer need to configure it explicitly,
        please remove this line from your config files:

            config :ecto, :json_library, Jason

        """

      value ->
        IO.warn """
        The :json_library configuration for the :ecto application is deprecated.
        Please configure the :json_library in the driver instead:

            config #{inspect driver}, :json_library, #{inspect value}

        """
    end

    quote do
      @doc """
      A convenience function for SQL-based repositories that executes the given query.

      See `Ecto.Adapters.SQL.query/4` for more information.
      """
      def query(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query(get_dynamic_repo(), sql, params, opts)
      end

      @doc """
      A convenience function for SQL-based repositories that executes the given query.

      See `Ecto.Adapters.SQL.query!/4` for more information.
      """
      def query!(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query!(get_dynamic_repo(), sql, params, opts)
      end

      @doc """
      A convenience function for SQL-based repositories that translates the given query to SQL.

      See `Ecto.Adapters.SQL.to_sql/3` for more information.
      """
      def to_sql(operation, queryable) do
        Ecto.Adapters.SQL.to_sql(operation, get_dynamic_repo(), queryable)
      end

      @doc """
      A convenience function for SQL-based repositories that executes an EXPLAIN statement or similar
      depending on the adapter to obtain statistics for the given query.

      See `Ecto.Adapters.SQL.explain/4` for more information.
      """
      def explain(operation, queryable, opts \\ []) do
        Ecto.Adapters.SQL.explain(get_dynamic_repo(), operation, queryable, opts)
      end
    end
  end

  @doc false
  def ensure_all_started(driver, _config, type) do
    Application.ensure_all_started(driver, type)
  end

  @pool_opts [:timeout, :pool, :pool_size] ++
               [:queue_target, :queue_interval, :ownership_timeout]

  @doc false
  def init(connection, driver, config) do
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect driver} as a dependency:

          {#{inspect driver}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean --build ecto
      """
    end

    log = Keyword.get(config, :log, :debug)
    telemetry_prefix = Keyword.fetch!(config, :telemetry_prefix)
    telemetry = {config[:repo], log, telemetry_prefix ++ [:query]}

    config = adapter_config(config)
    opts = Keyword.take(config, @pool_opts)
    meta = %{telemetry: telemetry, sql: connection, opts: opts}
    {:ok, connection.child_spec(config), meta}
  end

  defp adapter_config(config) do
    if Keyword.has_key?(config, :pool_timeout) do
      message = """
      :pool_timeout option no longer has an effect and has been replaced with an improved queuing system.
      See \"Queue config\" in DBConnection.start_link/2 documentation for more information.
      """

      IO.warn(message)
    end

    config
    |> Keyword.delete(:name)
    |> Keyword.update(:pool, DBConnection.ConnectionPool, &normalize_pool/1)
  end

  defp normalize_pool(pool) do
    if Code.ensure_loaded?(pool) && function_exported?(pool, :unboxed_run, 2) do
      DBConnection.Ownership
    else
      pool
    end
  end

  @doc false
  def checkout(adapter_meta, opts, callback) do
    checkout_or_transaction(:run, adapter_meta, opts, callback)
  end

  @doc false
  def checked_out?(adapter_meta) do
    %{pid: pool} = adapter_meta
    get_conn(pool) != nil
  end

  ## Query

  @doc false
  def insert_all(adapter_meta, schema_meta, conn, header, rows, on_conflict, returning, placeholders, opts) do
    %{source: source, prefix: prefix} = schema_meta
    {_, conflict_params, _} = on_conflict
    {rows, params} = case rows do
      {%Ecto.Query{} = query, params} -> {query, Enum.reverse(params)}
      rows -> unzip_inserts(header, rows)
    end

    sql = conn.insert(prefix, source, header, rows, on_conflict, returning, placeholders)

    opts = if is_nil(Keyword.get(opts, :cache_statement)) do
      [{:cache_statement, "ecto_insert_all_#{source}"} | opts]
    else
      opts
    end

    all_params = placeholders ++ Enum.reverse(params, conflict_params)
    %{num_rows: num, rows: rows} =
      query!(adapter_meta, sql, all_params, opts)

    {num, rows}
  end

  defp unzip_inserts(header, rows) do
    Enum.map_reduce rows, [], fn fields, params ->
      Enum.map_reduce header, params, fn key, acc ->
        case :lists.keyfind(key, 1, fields) do
          {^key, {%Ecto.Query{} = query, query_params}} ->
            {{query, length(query_params)}, Enum.reverse(query_params, acc)}

          {^key, {:placeholder, placeholder_index}} ->
            {{:placeholder, Integer.to_string(placeholder_index)}, acc}

          {^key, value} -> {key, [value | acc]}

          false -> {nil, acc}
        end
      end
    end
  end

  @doc false
  def execute(adapter_meta, query_meta, prepared, params, opts) do
    %{num_rows: num, rows: rows} =
      execute!(adapter_meta, prepared, params, put_source(opts, query_meta))

    {num, rows}
  end

  defp execute!(adapter_meta, {:cache, update, {id, prepared}}, params, opts) do
    name = "ecto_" <> Integer.to_string(id)

    case sql_call(adapter_meta, :prepare_execute, [name, prepared], params, opts) do
      {:ok, query, result} ->
        update.({id, query})
        result
      {:error, err} ->
        raise_sql_call_error err
    end
  end

  defp execute!(adapter_meta, {:cached, update, reset, {id, cached}}, params, opts) do
    case sql_call(adapter_meta, :execute, [cached], params, opts) do
      {:ok, query, result} ->
        update.({id, query})
        result
      {:ok, result} ->
        result
      {:error, err} ->
        raise_sql_call_error err
      {:reset, err} ->
        reset.({id, String.Chars.to_string(cached)})
        raise_sql_call_error err
    end
  end

  defp execute!(adapter_meta, {:nocache, {_id, prepared}}, params, opts) do
    case sql_call(adapter_meta, :query, [prepared], params, opts) do
      {:ok, res} -> res
      {:error, err} -> raise_sql_call_error err
    end
  end

  @doc false
  def stream(adapter_meta, query_meta, prepared, params, opts) do
    do_stream(adapter_meta, prepared, params, put_source(opts, query_meta))
  end

  defp do_stream(adapter_meta, {:cache, _, {_, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp do_stream(adapter_meta, {:cached, _, _, {_, cached}}, params, opts) do
    prepare_stream(adapter_meta, String.Chars.to_string(cached), params, opts)
  end

  defp do_stream(adapter_meta, {:nocache, {_id, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp prepare_stream(adapter_meta, prepared, params, opts) do
    adapter_meta
    |> Ecto.Adapters.SQL.Stream.build(prepared, params, opts)
    |> Stream.map(fn(%{num_rows: nrows, rows: rows}) -> {nrows, rows} end)
  end

  defp raise_sql_call_error(%DBConnection.OwnershipError{} = err) do
    message = err.message <> "\nSee Ecto.Adapters.SQL.Sandbox docs for more information."
    raise %{err | message: message}
  end

  defp raise_sql_call_error(err), do: raise err

  @doc false
  def reduce(adapter_meta, statement, params, opts, acc, fun) do
    %{pid: pool, telemetry: telemetry, sql: sql, opts: default_opts} = adapter_meta
    opts = with_log(telemetry, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        sql
        |> apply(:stream, [conn, statement, params, opts])
        |> Enumerable.reduce(acc, fun)

      _ ->
        raise "cannot reduce stream outside of transaction"
    end
  end

  @doc false
  def into(adapter_meta, statement, params, opts) do
    %{pid: pool, telemetry: telemetry, sql: sql, opts: default_opts} = adapter_meta
    opts = with_log(telemetry, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        sql
        |> apply(:stream, [conn, statement, params, opts])
        |> Collectable.into()

      _ ->
        raise "cannot collect into stream outside of transaction"
    end
  end

  @doc false
  def struct(adapter_meta, conn, sql, operation, source, params, values, on_conflict, returning, opts) do
    opts = if is_nil(Keyword.get(opts, :cache_statement)) do
      [{:cache_statement, "ecto_#{operation}_#{source}_#{length(params)}"} | opts]
    else
      opts
    end

    case query(adapter_meta, sql, values, opts) do
      {:ok, %{rows: nil, num_rows: 1}} ->
        {:ok, []}

      {:ok, %{rows: [values], num_rows: 1}} ->
        {:ok, Enum.zip(returning, values)}

      {:ok, %{num_rows: 0}} ->
        if on_conflict == :nothing, do: {:ok, []}, else: {:error, :stale}

      {:ok, %{num_rows: num_rows}} when num_rows > 1 ->
        raise Ecto.MultiplePrimaryKeyError,
              source: source, params: params, count: num_rows, operation: operation

      {:error, err} ->
        case conn.to_constraints(err, source: source) do
          [] -> raise_sql_call_error err
          constraints -> {:invalid, constraints}
        end
    end
  end

  ## Transactions

  @doc false
  def transaction(adapter_meta, opts, callback) do
    checkout_or_transaction(:transaction, adapter_meta, opts, callback)
  end

  @doc false
  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, get_conn(pool))
  end

  @doc false
  def rollback(%{pid: pool}, value) do
    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn -> DBConnection.rollback(conn, value)
      _ -> raise "cannot call rollback outside of transaction"
    end
  end

  ## Migrations

  @doc false
  def execute_ddl(meta, conn, definition, opts) do
    ddl_logs =
      definition
      |> conn.execute_ddl()
      |> List.wrap()
      |> Enum.map(&query!(meta, &1, [], opts))
      |> Enum.flat_map(&conn.ddl_logs/1)

    {:ok, ddl_logs}
  end

  @doc false
  def raise_migration_pool_size_error do
    raise Ecto.MigrationError, """
    Migrations failed to run because the connection pool size is less than 2.

    Ecto requires a pool size of at least 2 to support concurrent migrators.
    When migrations run, Ecto uses one connection to maintain a lock and
    another to run migrations.

    If you are running migrations with Mix, you can increase the number
    of connections via the pool size option:

        mix ecto.migrate --pool-size 2

    If you are running the Ecto.Migrator programmatically, you can configure
    the pool size via your application config:

        config :my_app, Repo,
          ...,
          pool_size: 2 # at least
    """
  end

  ## Log

  defp with_log(telemetry, params, opts) do
    [log: &log(telemetry, params, &1, opts)] ++ opts
  end

  defp log({repo, log, event_name}, params, entry, opts) do
    %{
      connection_time: query_time,
      decode_time: decode_time,
      pool_time: queue_time,
      idle_time: idle_time,
      result: result,
      query: query
    } = entry

    source = Keyword.get(opts, :source)
    query_string = String.Chars.to_string(query)

    params =
      Enum.map(params, fn
        %Ecto.Query.Tagged{value: value} -> value
        value -> value
      end)

    acc =
      if idle_time, do: [idle_time: idle_time], else: []

    measurements =
      log_measurements(
        [query_time: query_time, decode_time: decode_time, queue_time: queue_time],
        0,
        acc
      )

    metadata = %{
      type: :ecto_sql_query,
      repo: repo,
      result: log_result(result),
      params: params,
      query: query_string,
      source: source,
      options: Keyword.get(opts, :telemetry_options, [])
    }

    if event_name = Keyword.get(opts, :telemetry_event, event_name) do
      :telemetry.execute(event_name, measurements, metadata)
    end

    case Keyword.get(opts, :log, log) do
      true ->
        Logger.log(
          log,
          fn -> log_iodata(measurements, metadata) end,
          ansi_color: sql_color(query_string)
        )

      false ->
        :ok

      level ->
        Logger.log(
          level,
          fn -> log_iodata(measurements, metadata) end,
          ansi_color: sql_color(query_string)
        )
    end

    :ok
  end

  defp log_measurements([{_, nil} | rest], total, acc),
    do: log_measurements(rest, total, acc)

  defp log_measurements([{key, value} | rest], total, acc),
    do: log_measurements(rest, total + value, [{key, value} | acc])

  defp log_measurements([], total, acc),
    do: Map.new([total_time: total] ++ acc)

  defp log_result({:ok, _query, res}), do: {:ok, res}
  defp log_result(other), do: other

  defp log_iodata(measurements, metadata) do
    %{
      params: params,
      query: query,
      result: result,
      source: source
    } = metadata

    [
      "QUERY",
      ?\s,
      log_ok_error(result),
      log_ok_source(source),
      log_time("db", measurements, :query_time, true),
      log_time("decode", measurements, :decode_time, false),
      log_time("queue", measurements, :queue_time, false),
      log_time("idle", measurements, :idle_time, true),
      ?\n,
      query,
      ?\s,
      inspect(params, charlists: false)
    ]
  end

  defp log_ok_error({:ok, _res}), do: "OK"
  defp log_ok_error({:error, _err}), do: "ERROR"

  defp log_ok_source(nil), do: ""
  defp log_ok_source(source), do: " source=#{inspect(source)}"

  defp log_time(label, measurements, key, force) do
    case measurements do
      %{^key => time} ->
        us = System.convert_time_unit(time, :native, :microsecond)
        ms = div(us, 100) / 10

        if force or ms > 0 do
          [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
        else
          []
        end

      %{} ->
        []
    end
  end

  ## Connection helpers

  defp checkout_or_transaction(fun, adapter_meta, opts, callback) do
    %{pid: pool, telemetry: telemetry, opts: default_opts} = adapter_meta
    opts = with_log(telemetry, [], opts ++ default_opts)

    callback = fn conn ->
      previous_conn = put_conn(pool, conn)

      try do
        callback.()
      after
        reset_conn(pool, previous_conn)
      end
    end

    apply(DBConnection, fun, [get_conn_or_pool(pool), callback, opts])
  end

  defp get_conn_or_pool(pool) do
    Process.get(key(pool), pool)
  end

  defp get_conn(pool) do
    Process.get(key(pool))
  end

  defp put_conn(pool, conn) do
    Process.put(key(pool), conn)
  end

  defp reset_conn(pool, conn) do
    if conn do
      put_conn(pool, conn)
    else
      Process.delete(key(pool))
    end
  end

  defp key(pool), do: {__MODULE__, pool}

  defp sql_color("SELECT" <> _), do: :cyan
  defp sql_color("ROLLBACK" <> _), do: :red
  defp sql_color("LOCK" <> _), do: :white
  defp sql_color("INSERT" <> _), do: :green
  defp sql_color("UPDATE" <> _), do: :yellow
  defp sql_color("DELETE" <> _), do: :red
  defp sql_color("begin" <> _), do: :magenta
  defp sql_color("commit" <> _), do: :magenta
  defp sql_color(_), do: nil
end
