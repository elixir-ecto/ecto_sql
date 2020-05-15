defmodule Ecto.Integration.MyXQLTypeTest do
  use ExUnit.Case, async: true

  import Ecto.Type
  alias Ecto.Adapters.MyXQL

  test "evaluates MyXQL boolean bit values" do
    assert adapter_load(MyXQL, :boolean, <<1>>) ==
             {:ok, true}

    assert adapter_load(MyXQL, :boolean, <<1::size(1)>>) ==
             {:ok, true}

    assert adapter_load(MyXQL, :boolean, <<0>>) ==
             {:ok, false}

    assert adapter_load(MyXQL, :boolean, <<0::size(1)>>) ==
             {:ok, false}
  end
end
