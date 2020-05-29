defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "explain options" do
    explain = TestRepo.explain(:all, Post)
    assert explain =~ "TODO"
  end
end
