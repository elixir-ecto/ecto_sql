defmodule Ecto.Migration.Runner do
  @moduledoc false
  use Agent, restart: :temporary

  require Logger

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Constraint
  alias Ecto.Migration.Command

  @doc """
  Runs the given migration.
  """
  def run(repo, version, module, direction, operation, migrator_direction, opts) do
    level = Keyword.get(opts, :log, :info)
    sql = Keyword.get(opts, :log_sql, false)
    log = %{level: level, sql: sql}
    args  = {self(), repo, module, direction, migrator_direction, log}

    {:ok, runner} = DynamicSupervisor.start_child(Ecto.MigratorSupervisor, {__MODULE__, args})
    metadata(runner, opts)

    log(level, "== Running #{version} #{inspect module}.#{operation}/0 #{direction}")
    {time, _} = :timer.tc(fn -> perform_operation(repo, module, operation) end)
    log(level, "== Migrated #{version} in #{inspect(div(time, 100_000) / 10)}s")

    stop()
  end

  @doc """
  Stores the runner metadata.
  """
  def metadata(runner, opts) do
    prefix = opts[:prefix]
    Process.put(:ecto_migration, %{runner: runner, prefix: prefix && to_string(prefix)})
  end

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link({parent, repo, module, direction, migrator_direction, log}) do
    Agent.start_link(fn ->
      Process.link(parent)

      %{
        direction: direction,
        repo: repo,
        migration: module,
        migrator_direction: migrator_direction,
        command: nil,
        subcommands: [],
        log: log,
        commands: [],
        config: repo.config()
      }
    end)
  end

  @doc """
  Stops the runner.
  """
  def stop() do
    Agent.stop(runner())
  end

  @doc """
  Accesses the given repository configuration.
  """
  def repo_config(key, default) do
    Agent.get(runner(), &Keyword.get(&1.config, key, default))
  end

  @doc """
  Returns the migrator command (up or down).

    * forward + up: up
    * forward + down: down
    * forward + change: up
    * backward + change: down

  """
  def migrator_direction do
    Agent.get(runner(), & &1.migrator_direction)
  end

  @doc """
  Gets the repo for this migration
  """
  def repo do
    Agent.get(runner(), & &1.repo)
  end

  @doc """
  Gets the prefix for this migration
  """
  def prefix do
    case Process.get(:ecto_migration) do
      %{prefix: prefix} -> prefix
      _ -> raise "could not find migration runner process for #{inspect self()}"
    end
  end

  @doc """
  Executes queue migration commands.

  Reverses the order commands are executed when doing a rollback
  on a change/0 function and resets commands queue.
  """
  def flush do
    %{commands: commands, direction: direction, repo: repo, log: log, migration: migration} =
      Agent.get_and_update(runner(), fn state -> {state, %{state | commands: []}} end)

    commands = if direction == :backward, do: commands, else: Enum.reverse(commands)

    for command <- commands do
      execute_in_direction(repo, migration, direction, log, command)
    end
  end

  @doc """
  Queues command tuples or strings for execution.

  Ecto.MigrationError will be raised when the server
  is in `:backward` direction and `command` is irreversible.
  """
  def execute(command) do
    reply =
      Agent.get_and_update(runner(), fn
        %{command: nil} = state ->
          {:ok, %{state | subcommands: [], commands: [command|state.commands]}}
        %{command: _} = state ->
          {:error, %{state | command: nil}}
      end)

    case reply do
      :ok ->
        :ok
      :error ->
        raise Ecto.MigrationError, "cannot execute nested commands"
    end
  end

  @doc """
  Starts a command.
  """
  def start_command(command) do
    reply =
      Agent.get_and_update(runner(), fn
        %{command: nil} = state ->
          {:ok, %{state | command: command}}
        %{command: _} = state ->
          {:error, %{state | command: command}}
      end)

    case reply do
      :ok ->
        :ok
      :error ->
        raise Ecto.MigrationError, "cannot execute nested commands"
    end
  end

  @doc """
  Queues and clears current command. Must call `start_command/1` first.
  """
  def end_command do
    Agent.update runner(), fn state ->
      {operation, object} = state.command
      command = {operation, object, Enum.reverse(state.subcommands)}
      %{state | command: nil, subcommands: [], commands: [command|state.commands]}
    end
  end

  @doc """
  Adds a subcommand to the current command. Must call `start_command/1` first.
  """
  def subcommand(subcommand) do
    reply =
      Agent.get_and_update(runner(), fn
        %{command: nil} = state ->
          {:error, state}
        state ->
          {:ok, update_in(state.subcommands, &[subcommand|&1])}
      end)

    case reply do
      :ok ->
        :ok
      :error ->
        raise Ecto.MigrationError, message: "cannot execute command outside of block"
    end
  end

  ## Execute

  defp execute_in_direction(repo, migration, :forward, log, %Command{up: up}) do
    log_and_execute_ddl(repo, migration, log, up)
  end

  defp execute_in_direction(repo, migration, :forward, log, command) do
    log_and_execute_ddl(repo, migration, log, command)
  end

  defp execute_in_direction(repo, migration, :backward, log, %Command{down: down}) do
    log_and_execute_ddl(repo, migration, log, down)
  end

  defp execute_in_direction(repo, migration, :backward, log, command) do
    if reversed = reverse(command) do
      log_and_execute_ddl(repo, migration, log, reversed)
    else
      raise Ecto.MigrationError, message:
        "cannot reverse migration command: #{command command}. " <>
        "You will need to explicitly define up/0 and down/0 in your migration"
    end
  end

  defp reverse({:create, %Index{} = index}),
    do: {:drop, index}
  defp reverse({:create_if_not_exists, %Index{} = index}),
    do: {:drop_if_exists, index}
  defp reverse({:drop, %Index{} = index}),
    do: {:create, index}
  defp reverse({:drop_if_exists, %Index{} = index}),
    do: {:create_if_not_exists, index}

  defp reverse({:create, %Table{} = table, _columns}),
    do: {:drop, table}
  defp reverse({:create_if_not_exists, %Table{} = table, _columns}),
    do: {:drop_if_exists, table}
  defp reverse({:rename, %Table{} = table_current, %Table{} = table_new}),
    do: {:rename, table_new, table_current}
  defp reverse({:rename, %Table{} = table, current_column, new_column}),
    do: {:rename, table, new_column, current_column}
  defp reverse({:alter,  %Table{} = table, changes}) do
    if reversed = table_reverse(changes, []) do
      {:alter, table, reversed}
    end
  end

  # It is not a good idea to reverse constraints because
  # we can't guarantee data integrity when applying them back.
  defp reverse({:create_if_not_exists, %Constraint{} = constraint}),
    do: {:drop_if_exists, constraint}
  defp reverse({:create, %Constraint{} = constraint}),
    do: {:drop, constraint}

  defp reverse(_command), do: false

  defp table_reverse([{:remove, name, type, opts}| t], acc) do
    table_reverse(t, [{:add, name, type, opts} | acc])
  end
  defp table_reverse([{:modify, name, type, opts} | t], acc) do
    case opts[:from] do
      nil -> false
      from -> table_reverse(t, [{:modify, name, from, Keyword.put(opts, :from, type)} | acc])
    end
  end
  defp table_reverse([{:add, name, _type, _opts} | t], acc) do
    table_reverse(t, [{:remove, name} | acc])
  end
  defp table_reverse([_ | _], _acc) do
    false
  end
  defp table_reverse([], acc) do
    acc
  end

  ## Helpers

  defp perform_operation(repo, module, operation) do
    if function_exported?(repo, :in_transaction?, 0) and repo.in_transaction?() do
      if function_exported?(module, :after_begin, 0) do
        module.after_begin()
      end

      result = apply(module, operation, [])

      if function_exported?(module, :before_commit, 0) do
        module.before_commit()
      end

      result
    else
      apply(module, operation, [])
    end

    flush()
  end

  defp runner do
    case Process.get(:ecto_migration) do
      %{runner: runner} -> runner
      _ -> raise "could not find migration runner process for #{inspect self()}"
    end
  end

  defp log_and_execute_ddl(repo, migration, log, {instruction, %Index{} = index}) do
    if index.concurrently do
      migration_config = migration.__migration__()

      if not migration_config[:disable_ddl_transaction] do
        IO.warn """
        Migration #{inspect(migration)} has set index `#{index.name}` on table \
        `#{index.table}` to concurrently but did not disable ddl transaction. \
        Please set:

            use Ecto.Migration
            @disable_ddl_transaction true

        """, []
      end

      if not migration_config[:disable_migration_lock] do
        IO.warn """
        Migration #{inspect(migration)} has set index `#{index.name}` on table \
        `#{index.table}` to concurrently but did not disable migration lock. \
        Please set:

            use Ecto.Migration
            @disable_migration_lock true

        """, []
      end
    end

    log_and_execute_ddl(repo, log, {instruction, index})
  end

  defp log_and_execute_ddl(repo, _migration, log, command) do
    log_and_execute_ddl(repo, log, command)
  end

  defp log_and_execute_ddl(_repo, _log, func) when is_function(func, 0) do
    func.()
    :ok
  end

  defp log_and_execute_ddl(repo, %{level: level, sql: sql}, command) do
    log(level, command(command))
    meta = Ecto.Adapter.lookup_meta(repo.get_dynamic_repo())
    {:ok, logs} = repo.__adapter__().execute_ddl(meta, command, timeout: :infinity, log: sql)

    Enum.each(logs, fn {level, message, metadata} ->
      Logger.log(level, message, metadata)
    end)

    :ok
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)

  defp command(ddl) when is_binary(ddl) or is_list(ddl),
    do: "execute #{inspect ddl}"

  defp command({:create, %Table{} = table, _}),
    do: "create table #{quote_name(table.prefix, table.name)}"
  defp command({:create_if_not_exists, %Table{} = table, _}),
    do: "create table if not exists #{quote_name(table.prefix, table.name)}"
  defp command({:alter, %Table{} = table, _}),
    do: "alter table #{quote_name(table.prefix, table.name)}"
  defp command({:drop, %Table{} = table}),
    do: "drop table #{quote_name(table.prefix, table.name)}"
  defp command({:drop_if_exists, %Table{} = table}),
    do: "drop table if exists #{quote_name(table.prefix, table.name)}"

  defp command({:create, %Index{} = index}),
    do: "create index #{quote_name(index.prefix, index.name)}"
  defp command({:create_if_not_exists, %Index{} = index}),
    do: "create index if not exists #{quote_name(index.prefix, index.name)}"
  defp command({:drop, %Index{} = index}),
    do: "drop index #{quote_name(index.prefix, index.name)}"
  defp command({:drop_if_exists, %Index{} = index}),
    do: "drop index if exists #{quote_name(index.prefix, index.name)}"
  defp command({:rename, %Table{} = current_table, %Table{} = new_table}),
    do: "rename table #{quote_name(current_table.prefix, current_table.name)} to #{quote_name(new_table.prefix, new_table.name)}"
  defp command({:rename, %Table{} = table, current_column, new_column}),
    do: "rename column #{current_column} to #{new_column} on table #{quote_name(table.prefix, table.name)}"

  defp command({:create, %Constraint{check: nil, exclude: nil}}),
    do: raise ArgumentError, "a constraint must have either a check or exclude option"
  defp command({:create, %Constraint{check: check, exclude: exclude}}) when is_binary(check) and is_binary(exclude),
    do: raise ArgumentError, "a constraint must not have both check and exclude options"
  defp command({:create, %Constraint{check: check} = constraint}) when is_binary(check),
    do: "create check constraint #{constraint.name} on table #{quote_name(constraint.prefix, constraint.table)}"
  defp command({:create, %Constraint{exclude: exclude} = constraint}) when is_binary(exclude),
    do: "create exclude constraint #{constraint.name} on table #{quote_name(constraint.prefix, constraint.table)}"
  defp command({:drop, %Constraint{} = constraint}),
    do: "drop constraint #{constraint.name} from table #{quote_name(constraint.prefix, constraint.table)}"
  defp command({:drop_if_exists, %Constraint{} = constraint}),
    do: "drop constraint if exists #{constraint.name} from table #{quote_name(constraint.prefix, constraint.table)}"

  defp quote_name(nil, name), do: quote_name(name)
  defp quote_name(prefix, name), do: quote_name(prefix) <> "." <> quote_name(name)
  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))
  defp quote_name(name), do: name
end
