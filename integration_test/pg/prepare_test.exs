defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  # Both sources share their first 51 bytes, so the default statement names
  # (ecto_insert_<source>_0) would be identical after PostgreSQL's 63-byte
  # truncation.
  @long_source "prepare_test_01234567890123456789012345678901234567"

  defmodule LongA do
    use Ecto.Schema

    schema "prepare_test_01234567890123456789012345678901234567_a" do
      field :x, :integer
    end
  end

  defmodule LongB do
    use Ecto.Schema

    schema "prepare_test_01234567890123456789012345678901234567_b_logs" do
      field :x, :integer
      field :y, :integer
    end
  end

  test "prepare option" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    # Uncached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert TestRepo.all(Post, prepare: :named) == [one, two]

    # Cached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert TestRepo.all(Post, prepare: :named) == [one, two]
  end

  test "statement names longer than 63 bytes do not collide on the server" do
    TestRepo.query!("CREATE TEMP TABLE #{@long_source}_a (id bigserial PRIMARY KEY, x integer)")

    TestRepo.query!(
      "CREATE TEMP TABLE #{@long_source}_b_logs (id bigserial PRIMARY KEY, x integer, y integer)"
    )

    assert %LongA{} = TestRepo.insert!(%LongA{x: 1})
    assert %LongB{} = TestRepo.insert!(%LongB{x: 1, y: 2})
    # Without distinct names within 63 bytes this raised 08P01: "bind message
    # supplies 1 parameters, but prepared statement ... requires 2".
    assert %LongA{} = TestRepo.insert!(%LongA{x: 3})
    assert %LongB{} = TestRepo.insert!(%LongB{x: 3, y: 4})
  end
end
