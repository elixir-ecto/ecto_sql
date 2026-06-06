defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  defp prepend(sql, opts) do
    {sql, opts} = Ecto.Adapters.SQL.prepend_label(sql, opts)
    {IO.iodata_to_binary(sql), opts}
  end

  describe "prepend_label/2" do
    test "without a label, passes sql and opts through unchanged" do
      assert prepend("SELECT 1", cache_statement: "ecto_all_posts") ==
               {"SELECT 1", [cache_statement: "ecto_all_posts"]}
    end

    test "prepends a leading comment block" do
      {sql, _opts} = prepend("INSERT INTO posts ...", label: "create_post_q")
      assert sql == "/* create_post_q */ INSERT INTO posts ..."
    end

    test "leaves opts untouched so prepared-statement caching is preserved" do
      opts = [label: "tag_q", cache_statement: "ecto_insert_posts_3", timeout: 5000]
      {_sql, returned_opts} = prepend("INSERT INTO posts ...", opts)

      assert returned_opts == opts
    end

    test "rejects label-delimiter sequences and null bytes" do
      for bad <- ["evil */ DROP", "evil /* nest", "with\0null"] do
        assert_raise ArgumentError, ~r/cannot contain/, fn ->
          Ecto.Adapters.SQL.prepend_label("X", label: bad)
        end
      end
    end

    test "rejects non-string labels" do
      assert_raise ArgumentError, ~r/must be a string/, fn ->
        Ecto.Adapters.SQL.prepend_label("X", label: 123)
      end
    end
  end
end
