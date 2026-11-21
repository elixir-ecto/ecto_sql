defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Adapters.SQL, only: [cache_statement_name: 2, cache_statement_name: 3]

  describe "cache_statement_name/3" do
    test "keeps names within the limit untouched" do
      assert cache_statement_name("ecto_insert_", "posts", "_0") == "ecto_insert_posts_0"
      assert cache_statement_name("ecto_insert_all_", "posts") == "ecto_insert_all_posts"
      assert cache_statement_name("ecto_insert_", :posts, "_0") == "ecto_insert_posts_0"

      exactly_63 = String.duplicate("a", 63 - byte_size("ecto_insert__0"))
      assert byte_size(cache_statement_name("ecto_insert_", exactly_63, "_0")) == 63

      assert cache_statement_name("ecto_insert_", exactly_63, "_0") ==
               "ecto_insert_#{exactly_63}_0"
    end

    test "caps long names at 63 bytes while keeping sources distinct" do
      # These two differ only after PostgreSQL's 63-byte truncation point.
      a =
        cache_statement_name(
          "ecto_insert_",
          "business_workplace_attendance_leave_comp_rest_minutes",
          "_0"
        )

      b =
        cache_statement_name(
          "ecto_insert_",
          "business_workplace_attendance_leave_comp_rest_minutes_event_logs",
          "_0"
        )

      assert byte_size(a) <= 63
      assert byte_size(b) <= 63
      assert a != b
      assert a =~ ~r/^ecto_insert_business_workplace_attendance_leave_comp_[0-9A-Z]+_0$/
      assert String.ends_with?(a, "_0")
      assert String.ends_with?(b, "_0")
    end

    test "does not split multibyte characters when truncating" do
      name = cache_statement_name("ecto_insert_", String.duplicate("é", 40), "_0")
      assert byte_size(name) <= 63
      assert String.valid?(name)
    end
  end
end
