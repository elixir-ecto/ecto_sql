defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "prepare option" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert TestRepo.all(Post, prepare: :named) == [one, two]
  end
end
