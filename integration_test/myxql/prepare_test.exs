defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "prepare option" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    stmt_count_query = "SHOW GLOBAL STATUS LIKE '%prepared_stmt_count%'"

    # Uncached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert %{rows: [[0]]} = TestRepo.query(stmt_count_query, [])
    assert TestRepo.all(Post, prepare: :named) == [one, two]
    assert %{rows: [[1]]} = TestRepo.query(stmt_count_query, [])

    # Cached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert %{rows: [[1]]} = TestRepo.query(stmt_count_query, [])
    assert TestRepo.all(Post, prepare: :named) == [one, two]
    assert %{rows: [[1]]} = TestRepo.query(stmt_count_query, [])
  end
end
