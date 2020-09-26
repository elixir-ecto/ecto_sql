defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  describe "explain" do
    test "select" do
      explain = TestRepo.explain(:all, from(p in Post, where: p.title == "explain_test", limit: 1))
      assert explain =~ "| Rows | Executes |"
      assert explain =~ "| Parallel | EstimateExecutions |"
      assert explain =~ "SELECT TOP(1)"
      assert explain =~ "explain_test"
    end

    test "delete" do
      explain = TestRepo.explain(:delete_all, Post)
      assert explain =~ "DELETE"
      assert explain =~ "p0"
    end

    test "update" do
      explain = TestRepo.explain(:update_all, from(p in Post, update: [set: [title: "new title"]]))
      assert explain =~ "UPDATE"
      assert explain =~ "p0"
      assert explain =~ "new title"
    end

    test "invalid" do
      assert_raise(Tds.Error, fn ->
        TestRepo.explain(:all, from(p in "posts", select: p.invalid, where: p.invalid == "title"))
      end)
    end
  end
end
