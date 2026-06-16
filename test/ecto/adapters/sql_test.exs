defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  defp comments(list) do
    {pre, post} = Ecto.Adapters.SQL.comments(list)
    {IO.iodata_to_binary(pre), IO.iodata_to_binary(post)}
  end

  defp wrap(sql, opts) do
    sql |> Ecto.Adapters.SQL.wrap_comments(opts) |> IO.iodata_to_binary()
  end

  describe "comments/1" do
    test "empty list renders nothing" do
      assert comments([]) == {"", ""}
    end

    test "renders :pre leading and :post trailing" do
      assert comments(pre: "list_users") == {"/* list_users */ ", ""}
      assert comments(post: "list_users") == {"", " /* list_users */"}
      assert comments(pre: "a", post: "b") == {"/* a */ ", " /* b */"}
    end

    test "preserves order and supports multiples" do
      assert comments(pre: "a", pre: "b") == {"/* a */ /* b */ ", ""}
    end

    test "rejects comment-delimiter sequences and null bytes" do
      for bad <- ["evil */ x", "evil /* x", "x\0y"] do
        assert_raise ArgumentError, ~r/cannot contain/, fn ->
          Ecto.Adapters.SQL.comments(pre: bad)
        end
      end
    end

    test "rejects bad shapes" do
      assert_raise ArgumentError, ~r/expected \{:pre/, fn ->
        Ecto.Adapters.SQL.comments(foo: "bar")
      end

      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Ecto.Adapters.SQL.comments("nope")
      end
    end
  end

  describe "wrap_comments/2" do
    test "wraps the sql with pre/post from the :comments option" do
      assert wrap("INSERT INTO posts ...", comments: [pre: "create_post", post: "v2"]) ==
               "/* create_post */ INSERT INTO posts ... /* v2 */"
    end

    test "is a no-op without the :comments option" do
      assert wrap("INSERT INTO posts ...", timeout: 5000) == "INSERT INTO posts ..."
    end
  end
end
