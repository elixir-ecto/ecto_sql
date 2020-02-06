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
  def loaders(:naive_datetime, type), do: [&datetime_decode/1, type]
  def loaders(:naive_datetime_usec, type), do: [&datetime_decode/1, type]
  def loaders(:utc_datetime, type), do: [&utc_datetime_decode/1, type]
  def loaders(:utc_datetime_usec, type), do: [&utc_datetime_decode/1, type]
  def loaders(:date, type), do: [&date_decode/1, type]
  def loaders(:time, type), do: [&time_decode/1, type]
  def loaders(_, type), do: [type]

  @impl true
  def dumpers({:embed, _}, type), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers({:map, _}, type), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers(:binary_id, type), do: [type, Tds.Types.UUID]
  def dumpers(:naive_datetime, type), do: [type, &naivedatetime_encode/1]
  def dumpers(:naive_datetime_usec, type), do: [type, &usec_naivedatetime_encode/1]
  def dumpers(:utc_datetime, type), do: [type, &naivedatetime_encode/1]
  def dumpers(:utc_datetime_usec, type), do: [type, &usec_naivedatetime_encode/1]
  def dumpers(:time, type), do: [type, &time_encode/1]
  def dumpers(_, type), do: [type]

  defp naivedatetime_encode(nil), do: {:ok, nil}

  defp naivedatetime_encode(%DateTime{} = val),
    do: DateTime.to_naive(val) |> naivedatetime_encode()

  defp naivedatetime_encode(%NaiveDateTime{} = val) do
    val = {_, _} = NaiveDateTime.to_erl(val)
    {:ok, val}
  rescue
    _ ->
      :error
  end

  defp usec_naivedatetime_encode(nil), do: {:ok, nil}

  defp usec_naivedatetime_encode(%DateTime{} = val),
    do: DateTime.to_naive(val) |> usec_naivedatetime_encode()

  defp usec_naivedatetime_encode(%NaiveDateTime{} = val) do
    {date, {h, m, s}} = NaiveDateTime.to_erl(val)
    {ms, _} = val.microsecond
    {:ok, {date, {h, m, s, ms}}}
  rescue
    _ -> :error
  end

  defp time_encode(t) do
    case t do
      %Time{} ->
        {h, m, s} = Time.to_erl(t)
        {ms, 0} = t.microsecond
        {:ok, {h, m, s, ms}}

      nil ->
        {:ok, nil}

      {_, _, _, _} ->
        {:ok, t}

      _ ->
        {:error, "MsSql adapter does not suport given time structure or format"}
    end
  end

  defp datetime_decode(nil), do: {:ok, nil}
  defp datetime_decode(%NaiveDateTime{} = date), do: {:ok, date}

  defp datetime_decode({date, {h, m, s, ms}}) do
    # we are loosing precision here!!!!
    cond do
      ms == 0 ->
        NaiveDateTime.from_erl({date, {h, m, s}})

      ms > 999_999 ->
        rms = Integer.floor_div(ms, 10)
        NaiveDateTime.from_erl({date, {h, m, s}}, {rms, 6})

      true ->
        NaiveDateTime.from_erl({date, {h, m, s}}, {ms, 6})
    end
  end

  defp utc_datetime_decode(nil), do: {:ok, nil}
  defp utc_datetime_decode(%DateTime{} = date), do: {:ok, date}
  defp utc_datetime_decode(%NaiveDateTime{} = dt), do: DateTime.from_naive(dt, "Etc/UTC")

  defp utc_datetime_decode({date, {h, m, s, ms}}) do
    # we are loosing precision here!!!!
    cond do
      ms == 0 ->
        NaiveDateTime.from_erl({date, {h, m, s}})

      ms > 999_999 ->
        rms = Integer.floor_div(ms, 10)
        NaiveDateTime.from_erl({date, {h, m, s}}, {rms, 6})

      true ->
        NaiveDateTime.from_erl({date, {h, m, s}}, {ms, 6})
    end
    |> case do
      {:ok, dt} -> utc_datetime_decode(dt)
      error -> error
    end
  end

  defp date_decode(value) when is_tuple(value), do: Date.from_erl(value)
  defp date_decode(value), do: {:ok, value}

  defp time_decode({h, m, s, ms}) do
    ms =
      cond do
        ms == 0 ->
          {0, 0}

        ms > 999_999 ->
          rms = Integer.floor_div(ms, 10)
          {rms, 6}

        true ->
          {ms, 6}
      end

    Time.from_erl({h, m, s}, ms)
  end

  defp time_decode(value), do: {:ok, value}

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

  @impl Ecto.Adapter.Storage
  def storage_status(opts) do
    database =
      Keyword.fetch!(opts, :database) || raise ":database is nil in repostory configuration"

    opts = Keyword.delete(opts, :database)

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
