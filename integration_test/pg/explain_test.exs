defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "explain" do
    assert_raise(ArgumentError, "bad boolean value 1", fn ->
      TestRepo.explain(:all, Post, whatever: "1")
    end)

    explain = TestRepo.explain(:all, Post, analyze: true, verbose: true)
    assert explain =~ "cost="
    assert explain =~ "actual time="
    assert explain =~ "loops="
    assert explain =~ "Output:"
    assert explain =~ ~r/Planning [T|t]ime:/
    assert explain =~ ~r/Execution [T|t]ime:/
  end
end
