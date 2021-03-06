defmodule Ecto.Integration.InsertAllTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query

  @tag :insert_all
  test "insert_all" do
    TestRepo.insert(%Post{
      id: 1,
      title: "A generic title"
    })

    source = from p in Post,
      select: %{
        id: p.id * 10,
        title: ^"foobar"
      }
    assert {1, _} = TestRepo.insert_all(Post, source, on_conflict: :replace_all)
    assert %Post{id: 10, title: "foobar"} = TestRepo.get(Post, 10)
  end
end
