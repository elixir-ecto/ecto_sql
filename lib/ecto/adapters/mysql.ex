defmodule Ecto.Adapters.MySQL do
  @moduledoc false

  @behaviour Ecto.Adapter

  defp error!() do
    raise "Ecto.Adapters.MySQL is obsolete, use Ecto.Adapters.MyXQL instead"
  end

  defmacro __before_compile__(_env), do: error!()

  def ensure_all_started(_, _), do: error!()

  def init(_), do: error!()

  def checkout(_, _, _), do: error!()

  def checked_out?(_), do: error!()

  def loaders(_, _), do: error!()

  def dumpers(_, _), do: error!()
end
