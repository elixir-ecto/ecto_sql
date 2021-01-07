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

  test "explain JSON format" do
    [explain] = TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000, format: :json) |> Jason.decode!()
    keys = explain["Plan"] |> Map.keys
    assert Enum.member?(keys, "Actual Loops")
    assert Enum.member?(keys, "Actual Rows")
    assert Enum.member?(keys, "Actual Startup Time")
  end

  test "explain MAP format" do
    [explain] = TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000, format: :map)
    keys = explain["Plan"] |> Map.keys
    assert Enum.member?(keys, "Actual Loops")
    assert Enum.member?(keys, "Actual Rows")
    assert Enum.member?(keys, "Actual Startup Time")
  end

  test "explain YAML format" do
    explain = TestRepo.explain(:all, Post, analyze: true, verbose: true, timeout: 20000, format: :yaml)
    assert explain =~ ~r/Plan:/
    assert explain =~ ~r/Node Type:/
    assert explain =~ ~r/Relation Name:/
  end
end
