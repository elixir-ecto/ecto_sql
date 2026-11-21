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

    test "rejects prefixes that MySQL/MariaDB treat as executable comments or hints" do
      for bad <- ["!40000 DROP TABLE posts", "+MAX_EXECUTION_TIME(1)", "M!100000 DROP"] do
        assert_raise ArgumentError, ~r/cannot start with/, fn ->
          Ecto.Adapters.SQL.comments(pre: bad)
        end

        assert_raise ArgumentError, ~r/cannot start with/, fn ->
          Ecto.Adapters.SQL.comments(post: bad)
        end
      end
    end

    # Regression: the space after `/*` is load-bearing. MySQL/MariaDB executable
    # comments (`/*!`, `/*M!`) and optimizer hints (`/*+`) only take effect when
    # the marker immediately follows `/*`, so the rendered form must always keep
    # a space between the delimiter and the comment text.
    test "always renders a space between /* and the comment text" do
      {pre, post} = comments(pre: "tag", post: "tag")
      assert pre == "/* tag */ "
      assert post == " /* tag */"
      refute pre =~ "/*t"
      refute post =~ "/*t"
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

  describe "put_default_cache_statement/2" do
    test "sets the default name" do
      opts = Ecto.Adapters.SQL.put_default_cache_statement([timeout: 5000], "ecto_insert_posts")
      assert Keyword.get(opts, :cache_statement) == "ecto_insert_posts"
    end

    test "honors an explicit :cache_statement" do
      opts = Ecto.Adapters.SQL.put_default_cache_statement([cache_statement: "mine"], "default")
      assert Keyword.get(opts, :cache_statement) == "mine"
    end

    test "skips the default when comments are given" do
      opts =
        Ecto.Adapters.SQL.put_default_cache_statement(
          [comments: [pre: "dyn_123"]],
          "ecto_insert_posts"
        )

      assert Keyword.get(opts, :cache_statement) == nil
    end

    test "an explicit :cache_statement wins even with comments" do
      opts =
        Ecto.Adapters.SQL.put_default_cache_statement(
          [comments: [pre: "static_tag"], cache_statement: "mine"],
          "default"
        )

      assert Keyword.get(opts, :cache_statement) == "mine"
    end

    test "an empty :comments list still gets the default" do
      opts = Ecto.Adapters.SQL.put_default_cache_statement([comments: []], "ecto_insert_posts")
      assert Keyword.get(opts, :cache_statement) == "ecto_insert_posts"
    end
  end
end
