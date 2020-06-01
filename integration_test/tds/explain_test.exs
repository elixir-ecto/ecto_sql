defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "explain options" do
    assert_raise(Tds.Error, "not supported yet", fn ->
      TestRepo.explain(:all, Post)
    end)
  end
end
