defmodule Ecto.Adapters.TdsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.Tds.Connection, as: SQL
  alias Ecto.Migration.Reference

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, :decimal

      has_many :comments, Ecto.Adapters.TdsTest.Schema2,
        references: :x,
        foreign_key: :z

      has_one :permalink, Ecto.Adapters.TdsTest.Schema3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    import Ecto.Query

    schema "schema2" do
      belongs_to :post, Ecto.Adapters.TdsTest.Schema,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    import Ecto.Query

    @schema_prefix "foo"
    schema "schema3" do
      field :binary, :binary
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _, _} = Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Tds, query)
    query
  end

  defp all(query), do: query |> SQL.all() |> IO.iodata_to_binary()
  defp update_all(query), do: query |> SQL.update_all() |> IO.iodata_to_binary()
  defp delete_all(query), do: query |> SQL.delete_all() |> IO.iodata_to_binary()
  defp execute_ddl(query), do: query |> SQL.execute_ddl() |> Enum.map(&IO.iodata_to_binary/1)

  defp insert(prefx, table, header, rows, on_conflict, returning, placeholders \\ []) do
    IO.iodata_to_binary(
      SQL.insert(prefx, table, header, rows, on_conflict, returning, placeholders)
    )
  end

  defp update(prefx, table, fields, filter, returning) do
    IO.iodata_to_binary(SQL.update(prefx, table, fields, filter, returning))
  end

  defp delete(prefx, table, filter, returning) do
    IO.iodata_to_binary(SQL.delete(prefx, table, filter, returning))
  end

  test "from" do
    query = Schema |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0}
  end

  test "from with hints" do
    query =
      Schema |> from(hints: ["MAXDOP 1", "OPTIMIZE FOR UNKNOWN"]) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 WITH (MAXDOP 1, OPTIMIZE FOR UNKNOWN)}
  end

  test "from with schema prefix" do
    query = Schema3 |> select([r], r.binary) |> plan()
    assert all(query) == ~s{SELECT s0.[binary] FROM [foo].[schema3] AS s0}
  end

  test "from with 2-part prefix" do
    query = Schema |> select([r], r.x) |> Map.put(:prefix, {"database", "db_schema"}) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [database].[db_schema].[schema] AS s0}
  end

  test "from with 3-part prefix" do
    query = Schema |> select([r], r.x) |> Map.put(:prefix, {"server", "database", "db_schema"}) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [server].[database].[db_schema].[schema] AS s0}
  end

  test "from without schema" do
    query = "schema" |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0}

    query = "schema" |> select([r], fragment("?", r)) |> plan()
    assert all(query) == ~s{SELECT s0 FROM [schema] AS s0}

    query = "Schema" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT S0.[x] FROM [Schema] AS S0}

    query = "0odel" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT t0.[x] FROM [0odel] AS t0}

    assert_raise Ecto.QueryError,
                 ~r"Tds adapter does not support selecting all fields from",
                 fn ->
                   query = from(m in "schema", select: [m]) |> plan()
                   all(query) == ~s{SELECT s0.* FROM [schema] AS s0}
                 end
  end

  test "from with subquery" do
    query = subquery("posts" |> select([r], %{x: r.x, y: r.y})) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM (SELECT sp0.[x] AS [x], sp0.[y] AS [y] FROM [posts] AS sp0) AS s0}

    query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x], s0.[z] FROM (SELECT sp0.[x] AS [x], sp0.[y] AS [z] FROM [posts] AS sp0) AS s0}

    query =
      subquery(subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r))
      |> select([r], r)
      |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x], s0.[z] FROM (SELECT ss0.[x] AS [x], ss0.[z] AS [z] FROM (SELECT ssp0.[x] AS [x], ssp0.[y] AS [z] FROM [posts] AS ssp0) AS ss0) AS s0}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))

    query =
      "comments"
      |> join(:inner, [c], p in subquery(posts), on: true)
      |> select([_, p], p.x)
      |> plan()

    assert all(query) ==
             "SELECT s1.[x] FROM [comments] AS c0 " <>
               "INNER JOIN (SELECT sp0.[x] AS [x], sp0.[y] AS [y] FROM [posts] AS sp0 WHERE (sp0.[title] = @1)) AS s1 ON 1 = 1"

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))

    query =
      "comments"
      |> join(:inner, [c], p in subquery(posts), on: true)
      |> select([_, p], p)
      |> plan()

    assert all(query) ==
             "SELECT s1.[x], s1.[z] FROM [comments] AS c0 " <>
               "INNER JOIN (SELECT sp0.[x] AS [x], sp0.[y] AS [z] FROM [posts] AS sp0 WHERE (sp0.[title] = @1)) AS s1 ON 1 = 1"

    posts =
      subquery("posts" |> where(title: parent_as(:comment).subtitle) |> select([r], r.title))

    query =
      "comments"
      |> from(as: :comment)
      |> join(:inner, [c], p in subquery(posts))
      |> select([_, p], p)
      |> plan()

    assert all(query) ==
             "SELECT s1.[title] FROM [comments] AS c0 " <>
               "INNER JOIN (SELECT sp0.[title] AS [title] FROM [posts] AS sp0 WHERE (sp0.[title] = c0.[subtitle])) AS s1 ON 1 = 1"
  end

  test "CTE" do
    initial_query =
      "categories"
      |> where([c], is_nil(c.parent_id))
      |> select([c], %{id: c.id, depth: fragment("1")})

    iteration_query =
      "categories"
      |> join(:inner, [c], t in "tree", on: t.id == c.parent_id)
      |> select([c, t], %{id: c.id, depth: fragment("? + 1", t.depth)})

    cte_query = initial_query |> union_all(^iteration_query)

    query =
      Schema
      |> recursive_ctes(true)
      |> with_cte("tree", as: ^cte_query)
      |> join(:inner, [r], t in "tree", on: t.id == r.category_id)
      |> select([r, t], %{x: r.x, category_id: t.id, depth: type(t.depth, :integer)})
      |> plan()

    assert all(query) ==
             ~s{WITH [tree] ([id],[depth]) AS (} <>
               ~s{SELECT sc0.[id] AS [id], 1 AS [depth] FROM [categories] AS sc0 WHERE (sc0.[parent_id] IS NULL) } <>
               ~s{UNION ALL } <>
               ~s{(SELECT c0.[id], t1.[depth] + 1 FROM [categories] AS c0 } <>
               ~s{INNER JOIN [tree] AS t1 ON t1.[id] = c0.[parent_id])) } <>
               ~s{SELECT s0.[x], t1.[id], CAST(t1.[depth] AS bigint) } <>
               ~s{FROM [schema] AS s0 } <>
               ~s{INNER JOIN [tree] AS t1 ON t1.[id] = s0.[category_id]}
  end

  @raw_sql_cte """
  SELECT * FROM categories WHERE c.parent_id IS NULL
  UNION ALL
  SELECT * FROM categories AS c, category_tree AS ct WHERE ct.id = c.parent_id
  """

  test "reference CTE in union" do
    comments_scope_query =
      "comments"
      |> where([c], is_nil(c.deleted_at))
      |> select([c], %{entity_id: c.entity_id, text: c.text})

    posts_query =
      "posts"
      |> join(:inner, [p], c in "comments_scope", on: c.entity_id == p.guid)
      |> select([p, c], [p.title, c.text])

    videos_query =
      "videos"
      |> join(:inner, [v], c in "comments_scope", on: c.entity_id == v.guid)
      |> select([v, c], [v.title, c.text])

    query =
      posts_query
      |> union_all(^videos_query)
      |> with_cte("comments_scope", as: ^comments_scope_query)
      |> plan()

    assert all(query) ==
             ~s{WITH [comments_scope] ([entity_id],[text]) AS (} <>
               ~s{SELECT sc0.[entity_id] AS [entity_id], sc0.[text] AS [text] } <>
               ~s{FROM [comments] AS sc0 WHERE (sc0.[deleted_at] IS NULL)) } <>
               ~s{SELECT p0.[title], c1.[text] } <>
               ~s{FROM [posts] AS p0 } <>
               ~s{INNER JOIN [comments_scope] AS c1 ON c1.[entity_id] = p0.[guid] } <>
               ~s{UNION ALL } <>
               ~s{(SELECT v0.[title], c1.[text] } <>
               ~s{FROM [videos] AS v0 } <>
               ~s{INNER JOIN [comments_scope] AS c1 ON c1.[entity_id] = v0.[guid])}
  end

  test "fragment CTE" do
    query =
      Schema
      |> recursive_ctes(true)
      |> with_cte("tree", as: fragment(@raw_sql_cte))
      |> join(:inner, [p], c in "tree", on: c.id == p.category_id)
      |> select([r], r.x)
      |> plan()

    assert_raise Ecto.QueryError, ~r"Tds adapter does not support fragment in CTE", fn ->
      all(query)
    end
  end

  test "CTE update_all" do
    cte_query =
      from(x in Schema, order_by: [asc: :id], limit: 10, lock: "MERGE JOIN", select: %{id: x.id})

    query =
      Schema
      |> with_cte("target_rows", as: ^cte_query)
      |> join(:inner, [row], target in "target_rows", on: target.id == row.id)
      |> select([r, t], r)
      |> update(set: [x: 123])
      |> plan(:update_all)

    assert update_all(query) ==
             ~s{WITH [target_rows] ([id]) AS } <>
               ~s{(SELECT TOP(10) ss0.[id] AS [id] FROM [schema] AS ss0 ORDER BY ss0.[id] OPTION (MERGE JOIN)) } <>
               ~s{UPDATE s0 } <>
               ~s{SET s0.[x] = 123 } <>
               ~s{OUTPUT INSERTED.[id], INSERTED.[x], INSERTED.[y], INSERTED.[z], INSERTED.[w] } <>
               ~s{FROM [schema] AS s0 } <>
               ~s{INNER JOIN [target_rows] AS t1 ON t1.[id] = s0.[id]}
  end

  test "CTE delete_all" do
    cte_query = from(x in Schema, order_by: [asc: :id], limit: 10, select: %{id: x.id})

    query =
      Schema
      |> with_cte("target_rows", as: ^cte_query)
      |> join(:inner, [row], target in "target_rows", on: target.id == row.id)
      |> select([r, t], r)
      |> plan(:delete_all)

    assert delete_all(query) ==
             ~s{WITH [target_rows] ([id]) AS } <>
               ~s{(SELECT TOP(10) ss0.[id] AS [id] FROM [schema] AS ss0 ORDER BY ss0.[id]) } <>
               ~s{DELETE s0 } <>
               ~s{OUTPUT DELETED.[id], DELETED.[x], DELETED.[y], DELETED.[z], DELETED.[w] } <>
               ~s{FROM [schema] AS s0 } <>
               ~s{INNER JOIN [target_rows] AS t1 ON t1.[id] = s0.[id]}
  end

  test "parent binding subquery and CTE" do
    initial_query =
      "categories"
      |> where([c], c.id == parent_as(:parent_category).id)
      |> select([:id, :parent_id])

    iteration_query =
      "categories"
      |> join(:inner, [c], t in "tree", on: t.parent_id == c.id)
      |> select([:id, :parent_id])

    cte_query = initial_query |> union_all(^iteration_query)
    
    breadcrumbs_query =
      "tree"
      |> recursive_ctes(true)
      |> with_cte("tree", as: ^cte_query)
      |> select([t], %{breadcrumbs: fragment("STRING_AGG(?, ' / ')", t.id)})

    query =
      from(c in "categories",
        as: :parent_category,
        left_lateral_join: b in subquery(breadcrumbs_query),
        select: %{id: c.id, breadcrumbs: b.breadcrumbs}
      )
      |> plan()

    assert all(query) ==
      ~s{SELECT c0.[id], s1.[breadcrumbs] FROM [categories] AS c0 } <>
      ~s{OUTER APPLY } <>
      ~s{(WITH [tree] ([id],[parent_id]) AS } <>
      ~s{(SELECT ssc0.[id] AS [id], ssc0.[parent_id] AS [parent_id] FROM [categories] AS ssc0 WHERE (ssc0.[id] = c0.[id]) } <>
      ~s{UNION ALL } <>
      ~s{(SELECT c0.[id], c0.[parent_id] FROM [categories] AS c0 } <>
      ~s{INNER JOIN [tree] AS t1 ON t1.[parent_id] = c0.[id])) } <>
      ~s{SELECT STRING_AGG(st0.[id], ' / ') AS [breadcrumbs] FROM [tree] AS st0) AS s1}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.[x], s0.[y] FROM [schema] AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> plan()
    assert all(query) == ~s{SELECT s0.[x], s0.[y] FROM [schema] AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> plan()
    assert all(query) == ~s{SELECT s0.[x], s0.[y] FROM [schema] AS s0}
  end

  test "aggregates" do
    query = Schema |> select([r], count(r.x)) |> plan()
    assert all(query) == ~s{SELECT count(s0.[x]) FROM [schema] AS s0}

    query = Schema |> select([r], count(r.x, :distinct)) |> plan()
    assert all(query) == ~s{SELECT count(DISTINCT s0.[x]) FROM [schema] AS s0}

    query = Schema |> select([r], count()) |> plan()
    assert all(query) == ~s{SELECT count(*) FROM [schema] AS s0}
  end

  test "aggregate filters" do
    query = Schema |> select([r], count(r.x) |> filter(r.x > 10)) |> plan()

    assert_raise Ecto.QueryError,
                 ~r/Tds adapter does not support aggregate filters in query/,
                 fn ->
                   all(query)
                 end
  end

  test "distinct" do
    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0.[x], s0.[y] FROM [schema] AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.[x], s0.[y] FROM [schema] AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0.[x], s0.[y] FROM [schema] AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.[x], s0.[y] FROM [schema] AS s0}

    assert_raise Ecto.QueryError,
                 ~r"DISTINCT with multiple columns is not supported by MsSQL",
                 fn ->
                   query =
                     Schema |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> plan()

                   all(query)
                 end
  end

  test "select with operation" do
    query = Schema |> select([r], r.x * 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] * 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x / 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] / 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x + 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] + 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x - 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] - 2 FROM [schema] AS s0}
  end

  test "where" do
    query = Schema |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 WHERE (s0.[x] = 42) AND (s0.[y] <> 43)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 ORDER BY s0.[x]}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 ORDER BY s0.[x], s0.[y]}

    query = Schema |> order_by([r], asc: r.x, desc: r.y) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 ORDER BY s0.[x], s0.[y] DESC}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0}

    for dir <- [:asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last] do
      assert_raise Ecto.QueryError, ~r"#{dir} is not supported in ORDER BY in MSSQL", fn ->
        Schema |> order_by([r], [{^dir, r.x}]) |> select([r], r.x) |> plan() |> all()
      end
    end
  end

  test "union and union all" do
    base_query =
      Schema |> select([r], r.x) |> order_by(fragment("rand")) |> offset(10) |> limit(5)

    union_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    union_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> union(^union_query1) |> union(^union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{UNION (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{UNION (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}

    query = base_query |> union_all(^union_query1) |> union_all(^union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{UNION ALL (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{UNION ALL (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}
  end

  test "except and except all" do
    base_query =
      Schema |> select([r], r.x) |> order_by(fragment("rand")) |> offset(10) |> limit(5)

    except_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    except_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> except(^except_query1) |> except(^except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{EXCEPT (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{EXCEPT (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}

    query = base_query |> except_all(^except_query1) |> except_all(^except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{EXCEPT ALL (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{EXCEPT ALL (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}
  end

  test "intersect and intersect all" do
    base_query =
      Schema |> select([r], r.x) |> order_by(fragment("rand")) |> offset(10) |> limit(5)

    intersect_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    intersect_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> intersect(^intersect_query1) |> intersect(^intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{INTERSECT (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{INTERSECT (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}

    query =
      base_query |> intersect_all(^intersect_query1) |> intersect_all(^intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM [schema] AS s0 } <>
               ~s{INTERSECT ALL (SELECT s0.[y] FROM [schema] AS s0 ORDER BY s0.[y] OFFSET 20 ROW FETCH NEXT 40 ROWS ONLY) } <>
               ~s{INTERSECT ALL (SELECT s0.[z] FROM [schema] AS s0 ORDER BY s0.[z] OFFSET 30 ROW FETCH NEXT 60 ROWS ONLY) } <>
               ~s{ORDER BY rand OFFSET 10 ROW FETCH NEXT 5 ROWS ONLY}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TOP(3) CAST(1 as bit) FROM [schema] AS s0}

    query = Schema |> order_by([r], r.x) |> offset([r], 5) |> select([], true) |> plan()

    assert_raise Ecto.QueryError, fn ->
      all(query)
    end

    query =
      Schema
      |> order_by([r], r.x)
      |> offset([r], 5)
      |> limit([r], 3)
      |> select([], true)
      |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 ORDER BY s0.[x] OFFSET 5 ROW FETCH NEXT 3 ROWS ONLY}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> plan()

    assert_raise Ecto.QueryError, fn ->
      all(query)
    end
  end

  test "lock" do
    query = Schema |> lock("NOLOCK") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 OPTION (NOLOCK)}

    query = Schema |> lock([p], fragment("UPDATE on ?", p)) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 OPTION (UPDATE on s0)}
  end

  test "string escape" do
    query = "schema" |> where(foo: "\'--  ") |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = N'''--  ')}

    query = "schema" |> where(foo: "ok str '; select 1; --") |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = N'ok str ''; select 1; --')}

    query = "schema" |> where(foo: "'") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = N'''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] = 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x != 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] <> 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x <= 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] <= 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x >= 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] >= 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x < 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] < 2 FROM [schema] AS s0}

    query = Schema |> select([r], r.x > 2) |> plan()
    assert all(query) == ~s{SELECT s0.[x] > 2 FROM [schema] AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], r.x) |> where([r], is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 WHERE (s0.[x] IS NULL)}

    query = Schema |> select([r], r.x) |> where([r], not is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 WHERE (NOT (s0.[x] IS NULL))}

    query = Schema |> select([r], r.x) |> where([r], r.x == is_nil(r.y)) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 WHERE (s0.[x] = (s0.[y] IS NULL))}
  end

  test "fragments" do
    query = Schema |> select([r], fragment("lower(?)", r.x)) |> plan()
    assert all(query) == ~s{SELECT lower(s0.[x]) FROM [schema] AS s0}

    query = Schema |> select([r], fragment("? COLLATE ?", r.x, literal(^"es_ES"))) |> plan()
    assert all(query) == ~s{SELECT s0.[x] COLLATE [es_ES] FROM [schema] AS s0}

    value = 13
    query = Schema |> select([r], fragment("lower(?)", ^value)) |> plan()
    assert all(query) == ~s{SELECT lower(@1) FROM [schema] AS s0}

    query = Schema |> select([], fragment(title: 2)) |> plan()

    assert_raise Ecto.QueryError,
                 ~r"Tds adapter does not support keyword or interpolated fragments",
                 fn ->
                   all(query)
                 end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 1)}

    query = "schema" |> where(foo: false) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 0)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = N'abc')}

    query = "schema" |> where(foo: <<0, ?a, ?b, ?c>>) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 0x00616263)}

    query = "schema" |> where(foo: 123) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 123.0)}
  end

  test "aliasing a selected value with selected_as/2" do
    query = "schema" |> select([s], selected_as(s.x, :integer)) |> plan()
    assert all(query) == ~s{SELECT s0.[x] AS [integer] FROM [schema] AS s0}

    query = "schema" |> select([s], s.x |> coalesce(0) |> sum() |> selected_as(:integer)) |> plan()
    assert all(query) == ~s{SELECT sum(coalesce(s0.[x], 0)) AS [integer] FROM [schema] AS s0}
  end

  test "order_by can reference the alias of a selected value with selected_as/1s" do
    query = "schema" |> select([s], selected_as(s.x, :integer)) |> order_by(selected_as(:integer)) |> plan()
    assert all(query) == ~s{SELECT s0.[x] AS [integer] FROM [schema] AS s0 ORDER BY [integer]}

    query = "schema" |> select([s], selected_as(s.x, :integer)) |> order_by([desc: selected_as(:integer)]) |> plan()
    assert all(query) == ~s{SELECT s0.[x] AS [integer] FROM [schema] AS s0 ORDER BY [integer] DESC}
  end

  test "tagged type" do
    query =
      Schema |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Tds.Ecto.UUID)) |> plan()

    assert all(query) == ~s{SELECT CAST(@1 AS uniqueidentifier) FROM [schema] AS s0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Schema, []) |> select([r], (r.x > 0 and r.y > ^(-z)) or true) |> plan()
    assert all(query) == ~s{SELECT ((s0.[x] > 0) AND (s0.[y] > @1)) OR 1 FROM [schema] AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> plan()
    assert all(query) == ~s{SELECT 0=1 FROM [schema] AS s0}

    query = Schema |> select([e], 1 in [1, e.x, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,s0.[x],3) FROM [schema] AS s0}

    query = Schema |> select([e], 1 in ^[]) |> plan()
    assert all(query) == ~s{SELECT 0=1 FROM [schema] AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (@1,@2,@3) FROM [schema] AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,@1,3) FROM [schema] AS s0}

    query = Schema |> select([e], 1 in fragment("foo")) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY(foo) FROM [schema] AS s0}

    query = Schema |> select([e], e.x == ^0 or e.x in ^[1, 2, 3] or e.x == ^4) |> plan()

    assert all(query) ==
             ~s{SELECT ((s0.[x] = @1) OR s0.[x] IN (@2,@3,@4)) OR (s0.[x] = @5) FROM [schema] AS s0}
  end

  test "in subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([p], p.id))
    query = "comments" |> where([c], c.post_id in subquery(posts)) |> select([c], c.x) |> plan()

    assert all(query) ==
             ~s{SELECT c0.[x] FROM [comments] AS c0 } <>
               ~s{WHERE (c0.[post_id] IN (SELECT sp0.[id] FROM [posts] AS sp0 WHERE (sp0.[title] = @1)))}

    posts = subquery("posts" |> where(title: parent_as(:comment).subtitle) |> select([p], p.id))

    query =
      "comments"
      |> from(as: :comment)
      |> where([c], c.post_id in subquery(posts))
      |> select([c], c.x)
      |> plan()

    assert all(query) ==
             ~s{SELECT c0.[x] FROM [comments] AS c0 } <>
               ~s{WHERE (c0.[post_id] IN (SELECT sp0.[id] FROM [posts] AS sp0 WHERE (sp0.[title] = c0.[subtitle])))}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([p], p.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 HAVING (s0.[x] = s0.[x])}

    query =
      Schema
      |> having([p], p.x == p.x)
      |> having([p], p.y == p.y)
      |> select([p], [p.y, p.x])
      |> plan()

    assert all(query) ==
             ~s{SELECT s0.[y], s0.[x] FROM [schema] AS s0 HAVING (s0.[x] = s0.[x]) AND (s0.[y] = s0.[y])}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([p], p.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 HAVING (s0.[x] = s0.[x])}

    query =
      Schema
      |> or_having([p], p.x == p.x)
      |> or_having([p], p.y == p.y)
      |> select([p], [p.y, p.x])
      |> plan()

    assert all(query) ==
             ~s{SELECT s0.[y], s0.[x] FROM [schema] AS s0 HAVING (s0.[x] = s0.[x]) OR (s0.[y] = s0.[y])}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 GROUP BY s0.[x]}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 GROUP BY 2}

    query = Schema3 |> group_by([r], 2) |> select([r], r.binary) |> plan()
    assert all(query) == ~s{SELECT s0.[binary] FROM [foo].[schema3] AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0 GROUP BY s0.[x], s0.[y]}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.[x] FROM [schema] AS s0}
  end

  test "interpolated values" do
    cte1 = "schema1" |> select([m], %{id: m.id, smth: ^true}) |> where([], fragment("?", ^1))
    union = "schema1" |> select([m], {m.id, ^true}) |> where([], fragment("?", ^5))
    union_all = "schema2" |> select([m], {m.id, ^false}) |> where([], fragment("?", ^6))

    query =
      "schema"
      |> with_cte("cte1", as: ^cte1)
      |> select([m], {m.id, ^true})
      |> join(:inner, [], Schema2, on: fragment("?", ^true))
      |> join(:inner, [], Schema2, on: fragment("?", ^false))
      |> where([], fragment("?", ^true))
      |> where([], fragment("?", ^false))
      |> having([], fragment("?", ^true))
      |> having([], fragment("?", ^false))
      |> group_by([], fragment("?", ^3))
      |> group_by([], fragment("?", ^4))
      |> union(^union)
      |> union_all(^union_all)
      |> order_by([], fragment("?", ^7))
      |> limit([], ^8)
      |> offset([], ^9)
      |> plan()

    result =
      ~s{WITH [cte1] ([id],[smth]) AS } <>
        ~s{(SELECT ss0.[id] AS [id], @1 AS [smth] FROM [schema1] AS ss0 WHERE (@2)) } <>
        ~s{SELECT s0.[id], @3 FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON @4 } <>
        ~s{INNER JOIN [schema2] AS s2 ON @5 } <>
        ~s{WHERE (@6) AND (@7) } <>
        ~s{GROUP BY @8, @9 HAVING (@10) AND (@11) } <>
        ~s{UNION (SELECT s0.[id], @12 FROM [schema1] AS s0 WHERE (@13)) } <>
        ~s{UNION ALL (SELECT s0.[id], @14 FROM [schema2] AS s0 WHERE (@15)) } <>
        ~s{ORDER BY @16 OFFSET @18 ROW FETCH NEXT @17 ROWS ONLY}

    assert all(query) == String.trim_trailing(result)
  end

  test "fragments allow ? to be escaped with backslash" do
    query =
      plan(
        from(e in "schema",
          where: fragment("? = \"query\\?\"", e.start_time),
          select: true
        )
      )

    result =
      "SELECT CAST(1 as bit) FROM [schema] AS s0 " <>
        "WHERE (s0.[start_time] = \"query?\")"

    assert all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Schema, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE s0 SET s0.[x] = 0 FROM [schema] AS s0}

    query = from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0, s0.[y] = s0.[y] + 1, s0.[z] = s0.[z] + -3 FROM [schema] AS s0}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]]) |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0 FROM [schema] AS s0 WHERE (s0.[x] = 123)}

    query = from(m in Schema, update: [set: [x: 0, y: 123]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE s0 SET s0.[x] = 0, s0.[y] = 123 FROM [schema] AS s0}

    query = from(m in Schema, update: [set: [x: ^0]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE s0 SET s0.[x] = @1 FROM [schema] AS s0}

    query =
      from(
        e in Schema,
        where: e.x == 123,
        update: [set: [x: 0]],
        join: q in Schema2,
        on: e.x == q.z
      )
      |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0 FROM [schema] AS s0 } <>
               ~s{INNER JOIN [schema2] AS s1 ON s0.[x] = s1.[z] WHERE (s0.[x] = 123)}
  end

  test "update all with subquery" do
    sub = from(p in Schema, where: p.x > ^10)

    query =
      Schema
      |> join(:inner, [p], p2 in subquery(sub), on: p.id == p2.id)
      |> update([_], set: [x: ^100])

    {planned_query, cast_params, dump_params} = Ecto.Adapter.Queryable.plan_query(:update_all, Ecto.Adapters.Tds, query)

    assert update_all(planned_query) ==
      ~s{UPDATE s0 SET s0.[x] = @1 FROM [schema] AS s0 INNER JOIN } <>
      ~S{(SELECT ss0.[id] AS [id], ss0.[x] AS [x], ss0.[y] AS [y], ss0.[z] AS [z], ss0.[w] AS [w] FROM [schema] AS ss0 WHERE (ss0.[x] > @2)) } <>
      ~S{AS s1 ON s0.[id] = s1.[id]}

    assert cast_params == [100, 10]
    assert dump_params == [100, 10]
  end

  test "update all with returning" do
    query = from(m in Schema, update: [set: [x: 0]]) |> select([m], m) |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0 OUTPUT INSERTED.[id], INSERTED.[x], INSERTED.[y], INSERTED.[z], INSERTED.[w] FROM [schema] AS s0}
  end

  test "update all with prefix" do
    query =
      from(m in Schema, update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0 FROM [prefix].[schema] AS s0}

    query =
      from(m in Schema, prefix: "first", update: [set: [x: 0]])
      |> Map.put(:prefix, "prefix")
      |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE s0 SET s0.[x] = 0 FROM [first].[schema] AS s0}
  end

  test "delete all" do
    query = Schema |> Queryable.to_query() |> plan()
    assert delete_all(query) == ~s{DELETE s0 FROM [schema] AS s0}

    query = from(e in Schema, where: e.x == 123) |> plan()
    assert delete_all(query) == ~s{DELETE s0 FROM [schema] AS s0 WHERE (s0.[x] = 123)}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> plan()

    assert delete_all(query) ==
             ~s{DELETE s0 FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON s0.[x] = s1.[z]}

    query = from(e in Schema, where: e.x == 123, join: q in Schema2, on: e.x == q.z) |> plan()

    assert delete_all(query) ==
             ~s{DELETE s0 FROM [schema] AS s0 } <>
               ~s{INNER JOIN [schema2] AS s1 ON s0.[x] = s1.[z] WHERE (s0.[x] = 123)}
  end

  test "delete all with returning" do
    query = Schema |> Queryable.to_query() |> select([m], m) |> plan()

    assert delete_all(query) ==
             ~s{DELETE s0 OUTPUT DELETED.[id], DELETED.[x], DELETED.[y], DELETED.[z], DELETED.[w] FROM [schema] AS s0}
  end

  test "delete all with prefix" do
    query = Schema |> Queryable.to_query() |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE s0 FROM [prefix].[schema] AS s0}

    query = Schema |> from(prefix: "first") |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE s0 FROM [first].[schema] AS s0}
  end

  ## Joins

  test "join" do
    query =
      Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON s0.[x] = s1.[z]}

    query =
      Schema
      |> join(:inner, [p], q in Schema2, on: p.x == q.z)
      |> join(:inner, [], Schema, on: true)
      |> select([], true)
      |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON s0.[x] = s1.[z] } <>
               ~s{INNER JOIN [schema] AS s2 ON 1 = 1}
  end

  test "join with hints" do
    assert Schema
           |> join(:inner, [p], q in Schema2, hints: ["USE INDEX FOO", "USE INDEX BAR"])
           |> select([], true)
           |> plan()
           |> all() ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [schema2] AS s1 WITH (USE INDEX FOO, USE INDEX BAR) ON 1 = 1}
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, on: q.z == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON s1.[z] = s1.[z]}
  end

  test "join without schema" do
    query =
      "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [posts] AS p0 INNER JOIN [comments] AS c1 ON p0.[x] = c1.[z]}
  end

  test "join with prefix" do
    query =
      Schema
      |> join(:inner, [p], q in Schema2, on: p.x == q.z)
      |> Map.put(:prefix, "prefix")
      |> select([], true)
      |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [prefix].[schema] AS s0 INNER JOIN [prefix].[schema2] AS s1 ON s0.[x] = s1.[z]}
  end

  test "join with single line fragment" do
    query =
      Schema
      |> join(
        :inner,
        [p],
        q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10)
      )
      |> select([p], {p.id, ^0})
      |> where([p], p.id > 0 and p.id < ^100)
      |> plan()

    assert all(query) ==
             ~s{SELECT s0.[id], @1 FROM [schema] AS s0 INNER JOIN } <>
               ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0.[x] AND s2.field = @2) AS f1 ON 1 = 1 } <>
               ~s{WHERE ((s0.[id] > 0) AND (s0.[id] < @3))}
  end

  test "join with multi-line fragment" do
    query =
      Schema
      |> join(
        :inner,
        [p],
        q in fragment(~S"""
          SELECT *
          FROM schema2 AS s2
          WHERE s2.id = ? AND s2.field = ?
        """, p.x, ^10)
      )
      |> select([p], {p.id, ^0})
      |> where([p], p.id > 0 and p.id < ^100)
      |> plan()

    assert all(query) ==
             ~s{SELECT s0.[id], @1 FROM [schema] AS s0 INNER JOIN } <>
               ~s{(  SELECT *\n } <>
               ~s{ FROM schema2 AS s2\n } <>
               ~s{ WHERE s2.id = s0.[x] AND s2.field = @2\n} <>
               ~s{) AS f1 ON 1 = 1 WHERE ((s0.[id] > 0) AND (s0.[id] < @3))}
  end

  test "inner lateral join with fragment" do
    query = Schema
            |> join(:inner_lateral, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p, q], {p.id, q.z})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.[id], f1.[z] FROM [schema] AS s0 CROSS APPLY } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0.[x] AND s2.field = @1) AS f1 } <>
           ~s{WHERE ((s0.[id] > 0) AND (s0.[id] < @2))}
  end

  test "left lateral join with fragment" do
    query = Schema
            |> join(:left_lateral, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p, q], {p.id, q.z})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.[id], f1.[z] FROM [schema] AS s0 OUTER APPLY } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0.[x] AND s2.field = @1) AS f1 } <>
           ~s{WHERE ((s0.[id] > 0) AND (s0.[id] < @2))}
  end

  test "join with fragment and on defined" do
    query =
      Schema
      |> join(:inner, [p], q in fragment("SELECT * FROM schema2"), on: q.id == p.id)
      |> select([p], {p.id, ^0})
      |> plan()

    assert all(query) ==
             "SELECT s0.[id], @1 FROM [schema] AS s0 INNER JOIN (SELECT * FROM schema2) AS f1 ON f1.[id] = s0.[id]"
  end

  test "join with query interpolation" do
    inner = Ecto.Queryable.to_query(Schema2)
    query = from(p in Schema, left_join: c in ^inner, select: {p.id, c.id}) |> plan()

    assert all(query) ==
             "SELECT s0.[id], s1.[id] FROM [schema] AS s0 LEFT OUTER JOIN [schema2] AS s1 ON 1 = 1"
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = plan(query)

    assert all(query) ==
             "SELECT s0.[id], s2.[id] FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON 1 = 1 INNER JOIN [schema2] AS s2 ON 1 = 1"
  end

  ## Associations

  test "association join belongs_to" do
    query = Schema2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [schema2] AS s0 INNER JOIN [schema] AS s1 ON s1.[x] = s0.[z]"
  end

  test "association join has_many" do
    query = Schema |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [schema2] AS s1 ON s1.[z] = s0.[x]"
  end

  test "association join has_one" do
    query = Schema |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [schema] AS s0 INNER JOIN [foo].[schema3] AS s1 ON s1.[id] = s0.[y]"
  end

  # Schema based

  test "insert" do
    # prefx, table, header, rows, on_conflict, returning, placeholders
    assert insert(nil, "schema", [:x, :y], [[:x, :y]], {:raise, [], []}, []) ==
             ~s{INSERT INTO [schema] ([x],[y]) VALUES (@1, @2)}

    assert insert(nil, "schema", [:x, :y], [[:x, :y], [nil, :y]], {:raise, [], []}, [:id]) ==
             ~s{INSERT INTO [schema] ([x],[y]) OUTPUT INSERTED.[id] VALUES (@1, @2),(DEFAULT, @3)}

    assert insert(nil, "schema", [:x, :y], [[:x, :y], [nil, :y]], {:raise, [], []}, [:id], [1, 2]) ==
             ~s{INSERT INTO [schema] ([x],[y]) OUTPUT INSERTED.[id] VALUES (@3, @4),(DEFAULT, @5)}

    assert insert(nil, "schema", [], [[]], {:raise, [], []}, [:id]) ==
             ~s{INSERT INTO [schema] OUTPUT INSERTED.[id] DEFAULT VALUES}

    assert insert("prefix", "schema", [], [[]], {:raise, [], []}, [:id]) ==
             ~s{INSERT INTO [prefix].[schema] OUTPUT INSERTED.[id] DEFAULT VALUES}
  end

  test "insert with query" do
    select_query = from("schema", select: [:id]) |> plan(:all)

    query =
      insert(
        nil,
        "schema",
        [:x, :y, :z],
        [[:x, {select_query, 2}, :z], [nil, nil, {select_query, 1}]],
        {:raise, [], []},
        []
      )

    assert query ==
             ~s{INSERT INTO [schema] ([x],[y],[z]) VALUES (@1, (SELECT s0.[id] FROM [schema] AS s0), @4),(DEFAULT, DEFAULT, (SELECT s0.[id] FROM [schema] AS s0))}
  end

  test "insert with query as rows" do
    query = from(s in "schema", select: %{ foo: fragment("3"), bar: s.bar }) |> plan(:all)
    query = insert(nil, "schema", [:foo, :bar], query, {:raise, [], []}, [:foo])

    assert query == ~s{INSERT INTO [schema] ([foo],[bar]) OUTPUT INSERTED.[foo] SELECT 3, s0.[bar] FROM [schema] AS s0}
  end

  test "update" do
    query = update(nil, "schema", [:id], [:x, :y], [])
    assert query == ~s{UPDATE [schema] SET [id] = @1 WHERE [x] = @2 AND [y] = @3}

    query = update(nil, "schema", [:x, :y], [:id], [:z])
    assert query == ~s{UPDATE [schema] SET [x] = @1, [y] = @2 OUTPUT INSERTED.[z] WHERE [id] = @3}

    query = update("prefix", "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE [prefix].[schema] SET [x] = @1, [y] = @2 WHERE [id] = @3}
  end

  test "delete" do
    query = delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM [schema] WHERE [x] = @1 AND [y] = @2}

    query = delete(nil, "schema", [:x, :y], [:z])
    assert query == ~s{DELETE FROM [schema] OUTPUT DELETED.[z] WHERE [x] = @1 AND [y] = @2}

    query = delete("prefix", "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM [prefix].[schema] WHERE [x] = @1 AND [y] = @2}
  end

  ## DDL

  import Ecto.Migration,
    only: [table: 1, table: 2, index: 2, index: 3, constraint: 2, constraint: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "create empty table" do
    create = {:create, table(:posts), []}

    assert execute_ddl(create) == ["CREATE TABLE [posts]; "]
  end

  test "create table" do
    create =
      {:create, table(:posts),
       [
         {:add, :name, :string, [default: "Untitled", size: 20, null: false]},
         {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
         {:add, :on_hand, :integer, [default: 0, null: true]},
         {:add, :likes, :"smallint unsigned", [default: 0, null: false]},
         {:add, :published_at, :"datetime(6)", [null: true]},
         {:add, :is_active, :boolean, [default: true]}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [posts] ([name] nvarchar(20) NOT NULL CONSTRAINT [DF__posts_name] DEFAULT (N'Untitled'),
             [price] numeric(8,2) CONSTRAINT [DF__posts_price] DEFAULT (expr),
             [on_hand] integer NULL CONSTRAINT [DF__posts_on_hand] DEFAULT (0),
             [likes] smallint unsigned NOT NULL CONSTRAINT [DF__posts_likes] DEFAULT (0),
             [published_at] datetime(6) NULL,
             [is_active] bit CONSTRAINT [DF__posts_is_active] DEFAULT (1));
             """
             |> remove_newlines
             |> Kernel.<>(" ")
           ]
  end

  test "create table with prefix" do
    create =
      {:create, table(:posts, prefix: :foo),
       [{:add, :category_0, %Reference{table: :categories}, []}]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [foo].[posts] ([category_0] BIGINT,
             CONSTRAINT [posts_category_0_fkey] FOREIGN KEY ([category_0]) REFERENCES [foo].[categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION);
             """
             |> remove_newlines
             |> Kernel.<>(" ")
           ]
  end

  test "create table with reference" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_0, %Reference{table: :categories}, []},
         {:add, :category_1, %Reference{table: :categories, name: :foo_bar}, []},
         {:add, :category_2, %Reference{table: :categories, on_delete: :nothing}, []},
         {:add, :category_3, %Reference{table: :categories, on_delete: :delete_all},
          [null: false]},
         {:add, :category_4, %Reference{table: :categories, on_delete: :nilify_all}, []},
         {:add, :category_5, %Reference{table: :categories, prefix: :foo, on_delete: :nilify_all},
          []},
         {:add, :category_6, %Reference{table: :categories, with: [here: :there], on_delete: :nilify_all}, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [posts] ([id] int IDENTITY(1,1),
             [category_0] BIGINT,
             CONSTRAINT [posts_category_0_fkey] FOREIGN KEY ([category_0]) REFERENCES [categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION,
             [category_1] BIGINT,
             CONSTRAINT [foo_bar] FOREIGN KEY ([category_1]) REFERENCES [categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION,
             [category_2] BIGINT,
             CONSTRAINT [posts_category_2_fkey] FOREIGN KEY ([category_2]) REFERENCES [categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION,
             [category_3] BIGINT NOT NULL,
             CONSTRAINT [posts_category_3_fkey] FOREIGN KEY ([category_3]) REFERENCES [categories]([id]) ON DELETE CASCADE ON UPDATE NO ACTION,
             [category_4] BIGINT,
             CONSTRAINT [posts_category_4_fkey] FOREIGN KEY ([category_4]) REFERENCES [categories]([id]) ON DELETE SET NULL ON UPDATE NO ACTION,
             [category_5] BIGINT,
             CONSTRAINT [posts_category_5_fkey] FOREIGN KEY ([category_5]) REFERENCES [foo].[categories]([id]) ON DELETE SET NULL ON UPDATE NO ACTION,
             [category_6] BIGINT,
             CONSTRAINT [posts_category_6_fkey] FOREIGN KEY ([category_6],[here]) REFERENCES [categories]([id],[there]) ON DELETE SET NULL ON UPDATE NO ACTION,
             CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]));
             """
             |> remove_newlines
             |> Kernel.<>(" ")
           ]
  end

  test "create table with options" do
    create =
      {:create, table(:posts, options: "WITH FOO=BAR"),
       [{:add, :id, :serial, [primary_key: true]}, {:add, :created_at, :datetime, []}]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts] ([id] int IDENTITY(1,1), [created_at] datetime,
               CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id])) WITH FOO=BAR;
               """
               |> remove_newlines
               |> Kernel.<>(" ")
             ]
  end

  test "create table with composite key" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :integer, [primary_key: true]},
         {:add, :b, :integer, [primary_key: true]},
         {:add, :name, :string, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [posts] ([a] integer, [b] integer, [name] nvarchar(255),
             CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([a],[b]));
             """
             |> remove_newlines
             |> Kernel.<>(" ")
           ]
  end

  test "create table with binary column and UTF-8 default" do
    create = {:create, table(:blobs), [{:add, :blob, :binary, [default: "foo"]}]}

    assert execute_ddl(create) ==
             [
               "CREATE TABLE [blobs] ([blob] varbinary(max) CONSTRAINT [DF__blobs_blob] DEFAULT (N'foo')); "
             ]
  end

  test "create table with binary column and hex bytea literal default" do
    create = {:create, table(:blobs), [{:add, :blob, :binary, [default: "\\x666F6F", size: 16]}]}

    assert execute_ddl(create) ==
             [
               "CREATE TABLE [blobs] ([blob] varbinary(16) CONSTRAINT [DF__blobs_blob] DEFAULT (N'\\x666F6F')); "
             ]
  end

  test "create table with an unsupported type" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, {:a, :b, :c}, [default: %{}]}
       ]}

    assert_raise ArgumentError,
                 "unsupported type `{:a, :b, :c}`. " <>
                   "The type can either be an atom, a string or a tuple of the form " <>
                   "`{:map, t}` where `t` itself follows the same conditions.",
                 fn -> execute_ddl(create) end
  end

  test "drop table" do
    drop = {:drop, table(:posts), :restrict}
    assert execute_ddl(drop) == ["DROP TABLE [posts]; "]

    drop_cascade = {:drop, table(:posts), :cascade}

    assert_raise ArgumentError, ~r"MSSQL does not support `CASCADE` in DROP TABLE commands", fn ->
      execute_ddl(drop_cascade)
    end
  end

  test "drop table with prefixes" do
    drop = {:drop, table(:posts, prefix: :foo), :restrict}
    assert execute_ddl(drop) == ["DROP TABLE [foo].[posts]; "]
  end

  test "alter table" do
    alter =
      {:alter, table(:posts),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:add, :author_id, %Reference{table: :author}, []},
         {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
         {:modify, :cost, :integer, [null: true, default: nil]},
         {:modify, :permalink_id, %Reference{table: :permalinks}, null: false},
         {:modify, :status, :string, from: :integer},
         {:modify, :user_id, :integer, from: %Reference{table: :users}},
         {:modify, :group_id, %Reference{table: :groups, column: :gid},
          from: %Reference{table: :groups}},
         {:remove, :summary}
       ]}

    expected_ddl = [
      """
      ALTER TABLE [posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF__posts_title] DEFAULT (N'Untitled');
      ALTER TABLE [posts] ADD [author_id] BIGINT;
      ALTER TABLE [posts] ADD CONSTRAINT [posts_author_id_fkey] FOREIGN KEY ([author_id]) REFERENCES [author]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
      ALTER TABLE [posts] ALTER COLUMN [price] numeric(8,2) NULL;
      IF (OBJECT_ID(N'[DF__posts_cost]', 'D') IS NOT NULL) ALTER TABLE [posts] DROP CONSTRAINT [DF__posts_cost]; ALTER TABLE [posts] ALTER COLUMN [cost] integer NULL;
      ALTER TABLE [posts] ALTER COLUMN [permalink_id] BIGINT NOT NULL;
      ALTER TABLE [posts] ADD CONSTRAINT [posts_permalink_id_fkey] FOREIGN KEY ([permalink_id]) REFERENCES [permalinks]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
      ALTER TABLE [posts] ALTER COLUMN [status] nvarchar(255); ALTER TABLE [posts] DROP CONSTRAINT [posts_user_id_fkey];
      ALTER TABLE [posts] ALTER COLUMN [user_id] integer;
      ALTER TABLE [posts] DROP CONSTRAINT [posts_group_id_fkey];
      ALTER TABLE [posts] ALTER COLUMN [group_id] BIGINT;
      ALTER TABLE [posts] ADD CONSTRAINT [posts_group_id_fkey] FOREIGN KEY ([group_id]) REFERENCES [groups]([gid]) ON DELETE NO ACTION ON UPDATE NO ACTION;
      ALTER TABLE [posts] DROP COLUMN [summary];
      """
      |> remove_newlines
      |> Kernel.<>(" ")
    ]

    assert execute_ddl(alter) == expected_ddl
  end

  test "alter table with prefix" do
    alter =
      {:alter, table(:posts, prefix: "foo"),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:modify, :price, :numeric, [precision: 8, scale: 2]},
         {:modify, :permalink_id, %Reference{table: :permalinks}, null: false},
         {:remove, :summary}
       ]}

    assert execute_ddl(alter) ==
             [
               """
               ALTER TABLE [foo].[posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF_foo_posts_title] DEFAULT (N'Untitled');
               ALTER TABLE [foo].[posts] ALTER COLUMN [price] numeric(8,2);
               ALTER TABLE [foo].[posts] ALTER COLUMN [permalink_id] BIGINT NOT NULL;
               ALTER TABLE [foo].[posts] ADD CONSTRAINT [posts_permalink_id_fkey] FOREIGN KEY ([permalink_id]) REFERENCES [foo].[permalinks]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
               ALTER TABLE [foo].[posts] DROP COLUMN [summary];
               """
               |> remove_newlines
               |> Kernel.<>(" ")
             ]
  end

  test "alter table with invalid reference opts" do
    alter =
      {:alter, table(:posts),
       [{:add, :author_id, %Reference{table: :author, validate: false}, []}]}

    assert_raise ArgumentError, "validate: false on references is not supported in Tds", fn ->
      execute_ddl(alter)
    end
  end

  test "create check constraint" do
    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0")}

    assert execute_ddl(create) ==
             [
               ~s|ALTER TABLE [products] ADD CONSTRAINT [price_must_be_positive] CHECK (price > 0); |
             ]

    create =
      {:create,
       constraint(:products, "price_must_be_positive", check: "price > 0", prefix: "foo")}

    assert execute_ddl(create) ==
             [
               ~s|ALTER TABLE [foo].[products] ADD CONSTRAINT [price_must_be_positive] CHECK (price > 0); |
             ]
  end

  test "create check constraint with invalid validate opts" do
    create =
      {:create,
       constraint(:products, "price_must_be_positive", check: "price > 0", validate: false)}

    assert_raise ArgumentError, "`:validate` is not supported by the Tds adapter", fn ->
      execute_ddl(create)
    end
  end

  test "drop constraint" do
    drop = {:drop, constraint(:products, "price_must_be_positive"), :restrict}

    assert execute_ddl(drop) ==
             [~s|ALTER TABLE [products] DROP CONSTRAINT [price_must_be_positive]; |]

    drop = {:drop, constraint(:products, "price_must_be_positive", prefix: "foo"), :restrict}

    assert execute_ddl(drop) ==
             [~s|ALTER TABLE [foo].[products] DROP CONSTRAINT [price_must_be_positive]; |]

    drop_cascade = {:drop, constraint(:products, "price_must_be_positive"), :cascade}

    assert_raise ArgumentError, ~r"MSSQL does not support `CASCADE` in DROP CONSTRAINT commands", fn ->
      execute_ddl(drop_cascade)
    end
  end

  test "drop_if_exists constraint" do
    drop = {:drop_if_exists, constraint(:products, "price_must_be_positive"), :restrict}

    assert execute_ddl(drop) ==
             [
               "IF NOT EXISTS (" <>
                 "SELECT * FROM [INFORMATION_SCHEMA].[CHECK_CONSTRAINTS] " <>
                 "WHERE [CONSTRAINT_NAME] = N'price_must_be_positive') " <>
                 "ALTER TABLE [products] DROP CONSTRAINT [price_must_be_positive]; "
             ]

    drop = {:drop_if_exists, constraint(:products, "price_must_be_positive", prefix: "foo"), :restrict}

    assert execute_ddl(drop) ==
             [
               "IF NOT EXISTS (" <>
                 "SELECT * FROM [INFORMATION_SCHEMA].[CHECK_CONSTRAINTS] " <>
                 "WHERE [CONSTRAINT_NAME] = N'price_must_be_positive' " <>
                 "AND [CONSTRAINT_SCHEMA] = N'foo') " <>
                 "ALTER TABLE [foo].[products] DROP CONSTRAINT [price_must_be_positive]; "
             ]

    drop_cascade = {:drop_if_exists, constraint(:products, "price_must_be_positive"), :cascade}

    assert_raise ArgumentError, ~r"MSSQL does not support `CASCADE` in DROP CONSTRAINT commands", fn ->
      execute_ddl(drop_cascade)
    end
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert execute_ddl(rename) == [~s|EXEC sp_rename 'posts', 'new_posts'|]
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert execute_ddl(rename) == [~s|EXEC sp_rename 'foo.posts', 'foo.new_posts'|]
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}

    assert execute_ddl(rename) ==
             ["EXEC sp_rename 'posts.given_name', 'first_name', 'COLUMN'"]
  end

  test "rename column in table with prefixes" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}

    assert execute_ddl(rename) ==
             ["EXEC sp_rename 'foo.posts.given_name', 'first_name', 'COLUMN'"]
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}

    assert execute_ddl(create) ==
             [
               "CREATE INDEX [posts_category_id_permalink_index] ON [posts] ([category_id], [permalink]);"
             ]

    create =
      {:create,
       index(:posts, ["[category_id] ASC", "[permalink] DESC"], name: "IX_posts_by_category")}

    assert execute_ddl(create) ==
             [
               ~s|CREATE INDEX [IX_posts_by_category] ON [posts] ([category_id] ASC, [permalink] DESC);|
             ]
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}

    assert execute_ddl(create) ==
             [
               ~s|CREATE INDEX [posts_category_id_permalink_index] ON [foo].[posts] ([category_id], [permalink]);|
             ]
  end

  test "create index with prefix if not exists" do
    create = {:create_if_not_exists, index(:posts, [:category_id, :permalink], prefix: :foo)}

    assert execute_ddl(create) ==
             [
               """
               IF NOT EXISTS (SELECT name FROM sys.indexes
               WHERE name = N'posts_category_id_permalink_index'
               AND object_id = OBJECT_ID(N'foo.posts'))
               CREATE INDEX [posts_category_id_permalink_index] ON [foo].[posts] ([category_id], [permalink]);
               """
               |> remove_newlines
             ]
  end

  test "create index asserting concurrency" do
    create = {:create, index(:posts, [:permalink], name: "posts$main", concurrently: true)}

    assert execute_ddl(create) ==
             [~s|CREATE INDEX [posts$main] ON [posts] ([permalink]) WITH(ONLINE=ON);|]
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}

    assert execute_ddl(create) ==
             [~s|CREATE UNIQUE INDEX [posts_permalink_index] ON [posts] ([permalink]);|]

    create = {:create, index(:posts, [:permalink], unique: true, prefix: :foo)}

    assert execute_ddl(create) ==
             [~s|CREATE UNIQUE INDEX [posts_permalink_index] ON [foo].[posts] ([permalink]);|]
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}

    assert_raise ArgumentError, ~r"MSSQL does not support `using` in indexes", fn ->
      execute_ddl(create)
    end
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main"), :restrict}
    assert execute_ddl(drop) == [~s|DROP INDEX [posts$main] ON [posts]; |]

    drop_cascade = {:drop, index(:posts, [:id], name: "posts$main"), :cascade}

    assert_raise ArgumentError, ~r"MSSQL does not support `CASCADE` in DROP INDEX commands", fn ->
      execute_ddl(drop_cascade)
    end
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo), :restrict}

    assert execute_ddl(drop) ==
             [~s|DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts]; |]
  end

  test "drop index with prefix if exists" do
    drop =
      {:drop_if_exists,
       index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo), :restrict}

    assert execute_ddl(drop) ==
             [
               """
               IF EXISTS (SELECT name FROM sys.indexes
               WHERE name = N'posts_category_id_permalink_index'
               AND object_id = OBJECT_ID(N'foo.posts'))
               DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts];
               """
               |> remove_newlines
               |> Kernel.<>(" ")
             ]

    drop_cascade =
      {:drop_if_exists,
      index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo), :cascade}

    assert_raise ArgumentError, ~r"MSSQL does not support `CASCADE` in DROP INDEX commands", fn ->
      execute_ddl(drop_cascade)
    end
  end

  test "drop index asserting concurrency" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true), :restrict}
    assert execute_ddl(drop) == [~s|DROP INDEX [posts$main] ON [posts] LOCK=NONE; |]
  end

  defp remove_newlines(string) when is_binary(string) do
    string |> String.trim() |> String.replace("\n", " ")
  end
end
