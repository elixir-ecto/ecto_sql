defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "prepare option" do
    TestRepo.insert!(%Post{title: "one"})

    stmt_count_query = "SHOW GLOBAL STATUS LIKE '%prepared_stmt_count%'"
    assert %{rows: [[_, orig_count]]} = TestRepo.query!(stmt_count_query, [])
    orig_count = String.to_integer(orig_count)

    query = from p in Post, select: fragment("'mxql test prepare option'")

    # Uncached
    assert TestRepo.all(query, prepare: :unnamed) == ["mxql test prepare option"]
    %{rows: [[_, new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert String.to_integer(new_count) == orig_count

    assert TestRepo.all(query, prepare: :named) == ["mxql test prepare option"]
    assert %{rows: [[_, new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert String.to_integer(new_count) == orig_count + 1

    # Cached
    assert TestRepo.all(query, prepare: :unnamed) == ["mxql test prepare option"]
    assert %{rows: [[_, new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert String.to_integer(new_count) == orig_count + 1

    assert TestRepo.all(query, prepare: :named) == ["mxql test prepare option"]
    assert %{rows: [[_, new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert String.to_integer(new_count) == orig_count + 1
  end
end
