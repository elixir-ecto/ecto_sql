defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "explain options" do
    explain = TestRepo.explain(:all, Post, analyze: true)
    assert explain =~ "Execution Time:"

    explain = TestRepo.explain(:all, Post, verbose: true)
    assert explain =~ "Output:"

    explain = TestRepo.explain(:all, Post, costs: false)
    refute explain =~ "cost="

    explain = TestRepo.explain(:all, Post, analyze: false, buffers: true)
    assert explain =~ "Execution Time:"
  end
end
