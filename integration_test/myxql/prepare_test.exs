defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: false

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "prepare option" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    stmt_count_query = "SHOW GLOBAL STATUS LIKE '%prepared_stmt_count%'"
    assert %{rows: [[orig_count]]} = TestRepo.query!(stmt_count_query, [])

    # Uncached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    %{rows: [[new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert new_count == orig_count
    assert TestRepo.all(Post, prepare: :named) == [one, two]
    assert %{rows: [[new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert new_count == orig_count + 1

    # Cached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert %{rows: [[new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert new_count == orig_count + 1
    assert TestRepo.all(Post, prepare: :named) == [one, two]
    assert %{rows: [[new_count]]} = TestRepo.query!(stmt_count_query, [])
    assert new_count == orig_count + 1
  end
end
