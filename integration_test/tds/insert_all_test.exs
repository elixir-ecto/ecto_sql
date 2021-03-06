defmodule Ecto.Integration.InsertAllTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query

  @tag :insert_all
  test "insert_all" do
    assert {:ok, %Post{id: id}} = TestRepo.insert(%Post{
      title: "A generic title"
    })

    source = from p in Post,
      select: %{
        title: fragment("concat(?, ?)", ^"foobar", p.id)
      }

    expected_title = "foobar#{id}"
    assert {1, [%Post{title: ^expected_title}]} = TestRepo.insert_all(Post, source, returning: [:id, :title])
  end
end
