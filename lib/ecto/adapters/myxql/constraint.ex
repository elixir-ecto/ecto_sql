defmodule Ecto.Adapters.MyXQL.Constraint do
  @moduledoc false

  @behaviour Ecto.Adapters.SQL.Constraint

  @quotes ~w(" ' `)

  @impl true
  def to_constraints(%MyXQL.Error{mysql: %{name: :ER_DUP_ENTRY}, message: message}, opts) do
    with [_, quoted] <- :binary.split(message, " for key "),
         [_, index | _] <- :binary.split(quoted, @quotes, [:global]) do
      [unique: strip_source(index, opts[:source])]
    else
      _ -> []
    end
  end

  def to_constraints(%MyXQL.Error{mysql: %{name: name}, message: message}, _opts)
      when name in [:ER_ROW_IS_REFERENCED_2, :ER_NO_REFERENCED_ROW_2] do
    with [_, quoted] <- :binary.split(message, [" CONSTRAINT ", " FOREIGN KEY "]),
         [_, index | _] <- :binary.split(quoted, @quotes, [:global]) do
      [foreign_key: index]
    else
      _ -> []
    end
  end

  def to_constraints(
        %MyXQL.Error{mysql: %{name: :ER_CHECK_CONSTRAINT_VIOLATED}, message: message},
        _opts
      ) do
    with [_, quoted] <- :binary.split(message, ["Check constraint "]),
         [_, constraint | _] <- :binary.split(quoted, @quotes, [:global]) do
      [check: constraint]
    else
      _ -> []
    end
  end

  def to_constraints(_, _),
    do: []

  defp strip_source(name, nil), do: name
  defp strip_source(name, source), do: String.trim_leading(name, "#{source}.")
end
