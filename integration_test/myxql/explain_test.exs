defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  describe "explain" do
    test "select" do
      explain = TestRepo.explain(:all, from(p in Post, where: p.title == "title"), timeout: 20000)

      assert explain =~
               "| id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |"

      assert explain =~ "p0"
      assert explain =~ "SIMPLE"
      assert explain =~ "Using where"
    end

    test "delete" do
      explain = TestRepo.explain(:delete_all, Post)
      assert explain =~ "DELETE"
      assert explain =~ "p0"
    end

    test "update" do
      explain =
        TestRepo.explain(:update_all, from(p in Post, update: [set: [title: "new title"]]))

      assert explain =~ "UPDATE"
      assert explain =~ "p0"
    end

    test "invalid" do
      assert_raise(MyXQL.Error, fn ->
        TestRepo.explain(:all, from(p in "posts", select: p.invalid, where: p.invalid == "title"))
      end)
    end

    test "map format" do
      [explain] = TestRepo.explain(:all, Post, format: :map)
      keys = explain["query_block"] |> Map.keys()
      assert Enum.member?(keys, "cost_info")
      assert Enum.member?(keys, "select_id")
      assert Enum.member?(keys, "table")
    end

    test "explain without rolling back" do
      {:ok, {:ok, explain}} =
        TestRepo.transaction(fn ->
          TestRepo.explain(:delete_all, Post, wrap_in_transaction: false, timeout: 20000)
        end)

      assert explain =~ "DELETE"
      assert explain =~ "p0"
    end
  end
end
