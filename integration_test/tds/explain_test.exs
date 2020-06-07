defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "explain options" do
    assert_raise(Tds.Error, "EXPLAIN is not supported by Ecto.Adapters.TDS at the moment", fn ->
      TestRepo.explain(:all, Post)
    end)
  end
end
