defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  test "explain" do
    explain = TestRepo.explain(:all, Post, [analyze: true, verbose: true], [timeout: 20000])
    assert explain =~ "cost="
    assert explain =~ "actual time="
    assert explain =~ "loops="
    assert explain =~ "Output:"
    assert explain =~ ~r/Planning [T|t]ime:/
    assert explain =~ ~r/Execution [T|t]ime:/

    explain = TestRepo.explain(:delete_all, Post)
    assert explain =~ "Delete on posts p0"
    assert explain =~ "cost="

    explain = TestRepo.explain(:update_all, from(p in Post, update: [set: [title: "new title"]]))
    assert explain =~ "Update on posts p0"
    assert explain =~ "cost="

    assert_raise(ArgumentError, "bad boolean value 1", fn ->
      TestRepo.explain(:all, Post, whatever: "1")
    end)

    assert_raise(Postgrex.Error, fn ->
      TestRepo.explain(:all, Post, invalid: true)
    end)
  end
end
