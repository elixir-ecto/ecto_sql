defmodule Ecto.Integration.ExceptionsTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  test "on bad JSON interpolation" do
    assert_raise Postgrex.Error,
                 ~r/If you are trying to query a JSON field, the parameter may need to be interpolated/,
                 fn -> TestRepo.all(from p in Post, where: p.meta["field"] != "example") end
  end
end
