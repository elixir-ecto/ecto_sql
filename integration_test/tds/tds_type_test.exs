defmodule Ecto.Integration.TdsTypeTest do
  use ExUnit.Case, async: true

  import Ecto.Type
  alias Tds.Ecto.VarChar
  alias Ecto.Adapters.Tds

  @varchar_string "some string"

  test "dumps through the adapter" do
    assert adapter_dump(Tds, {:map, VarChar}, %{"a" => @varchar_string}) ==
             {:ok, %{"a" => @varchar_string}}
  end

  test "loads through the adapter" do
    assert adapter_load(Tds, {:map, VarChar}, %{"a" => {@varchar_string, :varchar}}) ==
             {:ok, %{"a" => @varchar_string}}

    assert adapter_load(Tds, {:map, VarChar}, %{"a" => @varchar_string}) ==
             {:ok, %{"a" => @varchar_string}}
  end
end
