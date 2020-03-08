defmodule Ecto.Adapters.MsSql do
  @moduledoc """
  Adapter module for MsSql.

  It uses `tds` for communicating to the database.

  ## Options

  MsSql options split in different categories described
  below. All options can be given via the repository
  configuration.

  ### Connection options
    * `:hostname` - Server hostname
    * `:port` - Server port (default: 1433)
    * `:username` - Username
    * `:password` - User password
    * `:database` - the database to connect to
    * `:pool` - The connection pool module, defaults to `DBConnection.ConnectionPool`
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs

  We also recommend developers to consult the `Tds.start_link/1` documentation for a complete list of all supported
  options for driver.

  ### Storage options
    * `:collation` - the database collation, used during database creation but it is ignored later

  """
  require Tds

  use Ecto.Adapters.SQL,
    driver: :tds,
    migration_lock: "(UPDLOCK)"

  require Logger

  @behaviour Ecto.Adapter.Storage
  # @conn Ecto.Adapters.MsSql.Connection

  ## Custom MSSQL types

  @doc false
  def autogenerate(:binary_id), do: Tds.Types.UUID.bingenerate()
  def autogenerate(:embed_id), do: Tds.Types.UUID.generate()
  def autogenerate(type), do: super(type)

  @doc false
  @impl true
  def loaders({:embed, _}, type), do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders({:map, _}, type), do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Tds.Types.UUID, type]
  def loaders(_, type), do: [type]

  @impl true
  def dumpers({:embed, _}, type), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers({:map, _}, type), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers(:binary_id, type), do: [type, Tds.Types.UUID]
  def dumpers(_, type), do: [type]


  defp bool_decode(<<0>>), do: {:ok, false}
  defp bool_decode(<<1>>), do: {:ok, true}
  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x) when is_boolean(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x), do: {:ok, Tds.json_library().decode!(x)}
  defp json_decode(x), do: {:ok, x}

  # Storage API
  @doc false
  @impl true
  def storage_up(opts) do
    database =
      Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"

    command =
      ~s(CREATE DATABASE [#{database}])
      |> concat_if(opts[:collation], &"COLLATE=#{&1}")

    case run_query(Keyword.put(opts, :database, "master"), command) do
      {:ok, _} ->
        :ok

      {:error, %Tds.Error{mssql: %{number: 1801}}} ->
        {:error, :already_up}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp concat_if(content, nil, _fun), do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @doc false
  @impl true
  def storage_down(opts) do
    database =
      Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"

    case run_query(Keyword.put(opts, :database, "master"), "DROP DATABASE [#{database}]") do
      {:ok, _} ->
        :ok

      {:error, %Tds.Error{mssql: %{number: 3701}}} ->
        {:error, :already_down}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(opts) do
    database =
      Keyword.fetch!(opts, :database) || raise ":database is nil in repostory configuration"

    opts = Keyword.put(opts, :database, "master")

    check_database_query =
      "SELECT [name] FROM [master].[sys].[databases] WHERE [name] = '#{database}'"

    case run_query(opts, check_database_query) do
      {:ok, %{num_rows: 0}} -> :down
      {:ok, %{num_rows: _}} -> :up
      other -> {:error, other}
    end
  end

  @impl true
  def supports_ddl_transaction? do
    true
  end

  defp run_query(opts, sql_command) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:tds)

    timeout = Keyword.get(opts, :timeout, 15_000)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    {:ok, pid} = Task.Supervisor.start_link()

    task =
      Task.Supervisor.async_nolink(pid, fn ->
        {:ok, conn} = Tds.start_link(opts)
        value = Ecto.Adapters.MsSql.Connection.execute(conn, sql_command, [], opts)
        GenServer.stop(conn)
        value
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, error}} ->
        {:error, error}

      {:exit, {%{__struct__: struct} = error, _}}
      when struct in [Tds.Error, DBConnection.Error] ->
        {:error, error}

      {:exit, reason} ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}

      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end
end
