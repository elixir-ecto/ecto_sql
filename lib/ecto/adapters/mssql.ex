defmodule Ecto.Adapters.MsSql do
  @moduledoc """
  Adapter module for MSSQL.

  It uses `tds` for communicating to the database
  and manages a connection pool with `poolboy`.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Mssql options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Compile time options
  Those options should be set in the config file and require
  recompilation in order to make an effect.
    * `:adapter` - The adapter name, in this case, `Tds.Ecto`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`

  ### Repo options
    * `:filter_null_on_unique_indexes` - Allows unique indexes to filter out null and only match on NOT NULL values

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 1433)
    * `:username` - Username
    * `:password` - User password
    * `:parameters` - Keyword list of connection parameters
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs

  ### Pool options

    * `:size` - The number of connections to keep in the pool
    * `:max_overflow` - The maximum overflow of connections (see poolboy docs)
    * `:lazy` - If false all connections will be started immediately on Repo startup (default: true)

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification

  """
  require Tds
  use Ecto.Adapters.SQL,
    driver: :tds,
    migration_lock: nil
  require Logger

  @behaviour Ecto.Adapter.Storage

  ## Custom MSSQL types

  @doc false
  def autogenerate(:binary_id), do: Tds.Types.UUID.bingenerate()
  def autogenerate(:embed_id),  do: Tds.Types.UUID.generate()
  def autogenerate(type),       do: super(type)

  @doc false
  def loaders({:embed, _} = type, _),       do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders({:map, _}, type),             do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(:map, type),                  do: [&json_decode/1, type]
  def loaders(:boolean, type),              do: [&bool_decode/1, type]
  def loaders(:binary_id, type),            do: [Tds.Types.UUID, type]
  def loaders(:naive_datetime, type),       do: [&datetime_decode/1, type]
  def loaders(:naive_datetime_usec, type),  do: [&datetime_decode/1, type]
  def loaders(_, type),                     do: [type]


  def dumpers({:embed, _} = type, _),       do: [&Ecto.Adapters.SQL.dump_embed(type, &1), &json_encode/1]
  def dumpers({:map, _} , type),            do: [&Ecto.Adapters.SQL.dump_embed(type, &1), &json_encode/1]
  def dumpers(:binary_id, type),            do: [type, Tds.Types.UUID]
  def dumpers(:naive_datetime, type),       do: [type, &datetime_encode/1]
  def dumpers(:naive_datetime_usec, type),  do: [type, &datetime_encode/1]
  def dumpers(_, type),                     do: [type]

  defp datetime_encode(nil), do: {:ok, nil}
  defp datetime_encode(val) do
    val  = {_, _} = NaiveDateTime.to_erl(val)
    {:ok, val}
  rescue
    _ ->
      :error
  end

  defp datetime_decode(nil), do: {:ok, nil}
  defp datetime_decode({date, {h, m, s, ms}}) do
    # we are loosing precision here!!!!
    cond do
      ms == 0 ->
        NaiveDateTime.from_erl({date, {h, m, s}})
      ms > 999999 ->
        rms = Integer.floor_div(ms, 10)
        NaiveDateTime.from_erl!({date, {h, m, s}}, {rms,  6})
      true ->
        NaiveDateTime.from_erl!({date, {h, m, s}}, {ms,  6})
    end
  end

  defp bool_decode(<<0>>),                do: {:ok, false}
  defp bool_decode(<<1>>),                do: {:ok, true}
  defp bool_decode(0),                    do: {:ok, false}
  defp bool_decode(1),                    do: {:ok, true}
  defp bool_decode(x) when is_boolean(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x),  do: {:ok, json_library().decode!(x)}
  defp json_decode(x),                    do: {:ok, x}

  defp json_encode(x),                    do: {:ok, json_library().encode!(x)}

  defp json_library(), do: Application.get_env(:tds, :json_library) || Jason

  # Storage API
  @doc false
  @impl true
  def storage_up(opts) do
    database =
      Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"

    command =
      ~s(CREATE DATABASE [#{database}])
      |> concat_if(opts[:lc_collate], &"COLLATE=#{&1}")

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

  def select_versions(table, opts) do
    case run_query(opts, ~s(SELECT version FROM [#{table}] ORDER BY version)) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, _} = error -> error
    end
  end

  defp run_query(opts, sql_command) do
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

  @impl true
  def supports_ddl_transaction? do
    true
  end
end
