defmodule Support.ConnectionHelpers do
  @doc """
  Reduces and intersperses a list in one pass.
  """
  def intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])

  def intersperse_reduce([], _separator, user_acc, _reducer, acc),
    do: {acc, user_acc}

  def intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
    {elem, user_acc} = reducer.(elem, user_acc)
    {[acc | elem], user_acc}
  end

  def intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
    {elem, user_acc} = reducer.(elem, user_acc)
    intersperse_reduce(rest, separator, user_acc, reducer, [acc, elem, separator])
  end
end
