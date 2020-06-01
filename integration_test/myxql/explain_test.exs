defmodule Ecto.Integration.ExplainTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  test "explain options" do
    explain = TestRepo.explain(:all, from(p in Post, where: p.title == "title"))

    assert explain =~
      "| id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |"

    assert explain =~ "p0"
    assert explain =~ "SIMPLE"
    assert explain =~ "Using where"
  end
end
