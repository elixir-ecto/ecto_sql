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
    assert {1, [%Post{id: 10, title: "foobar"}]} = TestRepo.insert_all(Post, source, conflict_target: [:id], on_conflict: :replace_all, returning: [:id, :title])
  end
end
