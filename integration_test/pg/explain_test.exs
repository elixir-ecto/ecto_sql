defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  test "explain" do
    explain = TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000)
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
      TestRepo.explain(:all, Post, analyze: "1")
    end)
  end

  @tag :plan_cache_mode
  test "explain with fallback generic plan" do
    # when using fallback generic plan , placeholders are used instead of values. i.e. $1 instead of 1
    query = from p in Post, where: p.visits == ^1 and p.title == ^"title"

    explain =
      TestRepo.explain(:all, query, plan: :fallback_generic, verbose: true, timeout: 20000)

    assert explain =~ "p0.visits = $1"
    assert explain =~ "(p0.title)::text = $2"

    # Works when no parameters are given
    TestRepo.explain(:all, Post, plan: :fallback_generic, verbose: true, timeout: 20000)
  end

  test "explain with fallback generic plan cannot use analyze" do
    msg = ~r/analyze cannot be used with a `:fallback_generic` explain plan/

    assert_raise ArgumentError, msg, fn ->
      TestRepo.explain(:all, Post, plan: :fallback_generic, analyze: true)
    end
  end

  test "explain with custom plan" do
    # when using custom plan, values are used instead of placeholders. i.e. 1 instead of $1
    query = from p in Post, where: p.visits == ^1 and p.title == ^"title"

    explain =
      TestRepo.explain(:all, query, plan: :custom, analyze: true, verbose: true, timeout: 20000)

    refute explain =~ "$1"
    refute explain =~ "$2"
    assert explain =~ "p0.visits = 1"
    assert explain =~ "(p0.title)::text = 'title'"
  end

  test "explain MAP format" do
    [explain] =
      TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000, format: :map)

    keys = explain["Plan"] |> Map.keys()
    assert Enum.member?(keys, "Actual Loops")
    assert Enum.member?(keys, "Actual Rows")
    assert Enum.member?(keys, "Actual Startup Time")
  end

  test "explain YAML format" do
    explain =
      TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000, format: :yaml)

    assert explain =~ ~r/Plan:/
    assert explain =~ ~r/Node Type:/
    assert explain =~ ~r/Relation Name:/
  end
end
