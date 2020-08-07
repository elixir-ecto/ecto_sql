defmodule Ecto.Adapters.Postgres do
  @moduledoc """
  Adapter module for PostgreSQL.

  It uses `Postgrex` for communicating to the database.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Postgres options split in different categories described
  below. All options can be given via the repository
  configuration:

      config :your_app, YourApp.Repo,
        ...

  ### Connection options

    * `:hostname` - Server hostname
    * `:socket_dir` - Connect to Postgres via UNIX sockets in the given directory
      The socket name is derived based on the port. This is the preferred method
      for configuring sockets and it takes precedence over the hostname. If you are
      connecting to a socket outside of the Postgres convention, use `:socket` instead;
    * `:socket` - Connect to Postgres via UNIX sockets in the given path.
      This option takes precedence over the `:hostname` and `:socket_dir`
    * `:username` - Username
    * `:password` - User password
    * `:port` - Server port (default: 5432)
    * `:database` - the database to connect to
    * `:maintenance_database` - Specifies the name of the database to connect to when
      creating or dropping the database. Defaults to `"postgres"`
    * `:pool` - The connection pool module, defaults to `DBConnection.ConnectionPool`
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs
    * `:parameters` - Keyword list of connection parameters
    * `:connect_timeout` - The timeout for establishing new connections (default: 5000)
    * `:prepare` - How to prepare queries, either `:named` to use named queries
      or `:unnamed` to force unnamed queries (default: `:named`)
    * `:socket_options` - Specifies socket configuration
    * `:show_sensitive_data_on_connection_error` - show connection data and
      configuration whenever there is an error attempting to connect to the
      database

  The `:socket_options` are particularly useful when configuring the size
  of both send and receive buffers. For example, when Ecto starts with a
  pool of 20 connections, the memory usage may quickly grow from 20MB to
  50MB based on the operating system default values for TCP buffers. It is
  advised to stick with the operating system defaults but they can be
  tweaked if desired:

      socket_options: [recbuf: 8192, sndbuf: 8192]

  We also recommend developers to consult the `Postgrex.start_link/1`
  documentation for a complete listing of all supported options.

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
      or `:unspecified` to remove encoding parameter (alternative engine compatibility)
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification
    * `:dump_path` - where to place dumped structures

  ### After connect callback

  If you want to execute a callback as soon as connection is established
  to the database, you can use the `:after_connect` configuration. For
  example, in your repository configuration you can add:

      after_connect: {Postgrex, :query!, ["SET search_path TO global_prefix", []]}

  You can also specify your own module that will receive the Postgrex
  connection as argument.

  ## Extensions

  Both PostgreSQL and its adapter for Elixir, Postgrex, support an
  extension system. If you want to use custom extensions for Postgrex
  alongside Ecto, you must define a type module with your extensions.
  Create a new file anywhere in your application with the following:

      Postgrex.Types.define(MyApp.PostgresTypes,
                            [MyExtension.Foo, MyExtensionBar] ++ Ecto.Adapters.Postgres.extensions())

  Once your type module is defined, you can configure the repository to use it:

      config :my_app, MyApp.Repo, types: MyApp.PostgresTypes

  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL,
    driver: :postgrex,
    migration_lock: "FOR UPDATE"

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Structure

  @default_maintenance_database "postgres"

  @doc """
  All Ecto extensions for Postgrex.
  """
  def extensions do
    []
  end

  # Support arrays in place of IN
  @impl true
  def dumpers({:map, _}, type),        do: [&Ecto.Type.embedded_dump(type, &1, :json)]
  def dumpers({:in, sub}, {:in, sub}), do: [{:array, sub}]
  def dumpers(:binary_id, type),       do: [type, Ecto.UUID]
  def dumpers(_, type),                do: [type]

  ## Storage API

  @impl true
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    encoding = if opts[:encoding] == :unspecified, do: nil, else: opts[:encoding] || "UTF8"
    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    command =
      ~s(CREATE DATABASE "#{database}")
      |> concat_if(encoding, &"ENCODING '#{&1}'")
      |> concat_if(opts[:template], &"TEMPLATE=#{&1}")
      |> concat_if(opts[:lc_ctype], &"LC_CTYPE='#{&1}'")
      |> concat_if(opts[:lc_collate], &"LC_COLLATE='#{&1}'")

    case run_query(command, opts) do
      {:ok, _} ->
        :ok
      {:error, %{postgres: %{code: :duplicate_database}}} ->
        {:error, :already_up}
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp concat_if(content, nil, _fun),  do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @impl true
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    command  = "DROP DATABASE \"#{database}\""
    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    case run_query(command, opts) do
      {:ok, _} ->
        :ok
      {:error, %{postgres: %{code: :invalid_catalog_name}}} ->
        {:error, :already_down}
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    check_database_query = "SELECT datname FROM pg_catalog.pg_database WHERE datname = '#{database}'"

    case run_query(check_database_query, opts) do
      {:ok, %{num_rows: 0}} -> :down
      {:ok, %{num_rows: _num_rows}} -> :up
      other -> {:error, other}
    end
  end

  @impl true
  def supports_ddl_transaction? do
    true
  end

  @impl true
  def structure_dump(default, config) do
    table = config[:migration_source] || "schema_migrations"
    with {:ok, versions} <- select_versions(table, config),
         {:ok, path} <- pg_dump(default, config),
         do: append_versions(table, versions, path)
  end

  defp select_versions(table, config) do
    case run_query(~s[SELECT version FROM public."#{table}" ORDER BY version], config) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, %{postgres: %{code: :undefined_table}}} -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp pg_dump(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    File.mkdir_p!(Path.dirname(path))

    case run_with_cmd("pg_dump", config, ["--file", path, "--schema-only", "--no-acl",
                                          "--no-owner", config[:database]]) do
      {_output, 0} ->
        {:ok, path}
      {output, _} ->
        {:error, output}
    end
  end

  defp append_versions(_table, [], path) do
    {:ok, path}
  end

  defp append_versions(table, versions, path) do
    sql = Enum.map_join(versions, &~s[INSERT INTO public."#{table}" (version) VALUES (#{&1});\n])

    File.open!(path, [:append], fn file ->
      IO.write(file, sql)
    end)

    {:ok, path}
  end

  @impl true
  def structure_load(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    args = ["--quiet", "--file", path, "-vON_ERROR_STOP=1",
            "--single-transaction", config[:database]]
    case run_with_cmd("psql", config, args) do
      {_output, 0} -> {:ok, path}
      {output, _}  -> {:error, output}
    end
  end

  ## Helpers

  defp run_query(sql, opts) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    task = Task.Supervisor.async_nolink(Ecto.Adapters.SQL.StorageSupervisor, fn ->
      {:ok, conn} = Postgrex.start_link(opts)

      value = Postgrex.query(conn, sql, [], opts)
      GenServer.stop(conn)
      value
    end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}
      {:ok, {:error, error}} ->
        {:error, error}
      {:exit, {%{__struct__: struct} = error, _}}
          when struct in [Postgrex.Error, DBConnection.Error] ->
        {:error, error}
      {:exit, reason}  ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}
      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end

  defp run_with_cmd(cmd, opts, opt_args) do
    unless System.find_executable(cmd) do
      raise "could not find executable `#{cmd}` in path, " <>
            "please guarantee it is available before running ecto commands"
    end

    env =
      [{"PGCONNECT_TIMEOUT", "10"}]
    env =
      if password = opts[:password] do
        [{"PGPASSWORD", password}|env]
      else
        env
      end

    args =
      []
    args =
      if username = opts[:username], do: ["-U", username|args], else: args
    args =
      if port = opts[:port], do: ["-p", to_string(port)|args], else: args

    host = opts[:hostname] || System.get_env("PGHOST") || "localhost"
    args = ["--host", host|args]
    args = args ++ opt_args
    System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  end
end
