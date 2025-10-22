defmodule Ecto.Adapters.SQL.Constraint do
  # TODO - add more docs around setting `:constraint_handler` globally

  @moduledoc """
  Specifies the constraint handling API
  """

  @doc """
  Receives the exception returned by `c:Ecto.Adapters.SQL.Connection.query/4`.

  The constraints are in the keyword list and must return the
  constraint type, like `:unique`, and the constraint name as
  a string, for example:

      [unique: "posts_title_index"]

  Must return an empty list if the error does not come
  from any constraint.
  """
  @callback to_constraints(exception :: Exception.t(), options :: Keyword.t()) :: Keyword.t()
end
