defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  import Ecto.Type
  alias Ecto.Adapters.{MyXQL, Postgres, Tds}

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>
  @mssql_uuid_binary <<140, 136, 224, 191, 89, 92, 179, 75, 173, 253, 113, 240, 184, 93, 61, 183>>

  # We don't effectively dump because we need to keep JSON encoding
  test "dumps through the adapter" do
    assert adapter_dump(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_dump(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_dump(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}
  end

  # Therefore we need to support both binaries and strings when loading
  test "loads through the adapter" do
    assert adapter_load(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_binary}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_binary}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @mssql_uuid_binary}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_load(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @uuid_string}) ==
           {:ok, %{"a" => @uuid_string}}
  end
end
