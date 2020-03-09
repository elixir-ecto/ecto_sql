defmodule Ecto.Adapters.TdsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.Tds.Connection, as: SQL
  alias Ecto.Migration.Reference

  defmodule Model do
    use Ecto.Schema

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, :decimal

      has_many :comments, Ecto.Adapters.TdsTest.Model2,
        references: :x,
        foreign_key: :z

      has_one :permalink, Ecto.Adapters.TdsTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Schema

    import Ecto.Query

    schema "model2" do
      belongs_to :post, Ecto.Adapters.TdsTest.Model,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Model3 do
    use Ecto.Schema

    import Ecto.Query

    @schema_prefix "foo"
    schema "model3" do
      field :binary, :binary
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _} = Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Tds, query)
    query
  end

  defp all(query), do: query |> SQL.all() |> IO.iodata_to_binary()
  defp update_all(query), do: query |> SQL.update_all() |> IO.iodata_to_binary()
  defp delete_all(query), do: query |> SQL.delete_all() |> IO.iodata_to_binary()
  defp execute_ddl(query), do: query |> SQL.execute_ddl() |> Enum.map(&IO.iodata_to_binary/1)

  defp insert(prefx, table, header, rows, on_conflict, returning) do
    IO.iodata_to_binary(SQL.insert(prefx, table, header, rows, on_conflict, returning))
  end

  defp update(prefx, table, fields, filter, returning) do
    IO.iodata_to_binary(SQL.update(prefx, table, fields, filter, returning))
  end

  defp delete(prefx, table, filter, returning) do
    IO.iodata_to_binary(SQL.delete(prefx, table, filter, returning))
  end

  test "from" do
    query = Model |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "from with hints" do
    query =
      Model |> from(hints: ["MAXDOP 1", "OPTIMIZE FOR UNKNOWN"]) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT m0.[x] FROM [model] AS m0 OPTION (MAXDOP 1, OPTIMIZE FOR UNKNOWN)}
  end

  test "from Model3 with schema foo" do
    query = Model3 |> select([r], r.binary) |> plan()
    assert all(query) == ~s{SELECT m0.[binary] FROM [foo].[model3] AS m0}
  end

  test "from without schema" do
    query = "model" |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}

    # probably not good idea to support "asterisk" but here it is :)
    assert_raise Ecto.QueryError,
                 ~r"Tds adapter does not support selecting all fields from",
                 fn ->
                   query = "model" |> select([r], fragment("?", r)) |> plan()
                   all(query) == ~s{SELECT m0.* FROM [model] AS m0}
                 end

    query = "Model" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT M0.[x] FROM [Model] AS M0}

    query = "0odel" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT t0.[x] FROM [0odel] AS t0}

    assert_raise Ecto.QueryError,
                 ~r"Tds adapter does not support selecting all fields from",
                 fn ->
                   query = from(m in "model", select: [m]) |> plan()
                   all(query) == ~s{SELECT m0.* FROM [model] AS m0}
                 end
  end

  test "from with subquery" do
    query = subquery("posts" |> select([r], %{x: r.x, y: r.y})) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x] FROM (SELECT p0.[x] AS [x], p0.[y] AS [y] FROM [posts] AS p0) AS s0}

    query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan()

    assert all(query) ==
             ~s{SELECT s0.[x], s0.[z] FROM (SELECT p0.[x] AS [x], p0.[y] AS [z] FROM [posts] AS p0) AS s0}
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
      Model
      |> recursive_ctes(true)
      |> with_cte("tree", as: ^cte_query)
      |> join(:inner, [r], t in "tree", on: t.id == r.category_id)
      |> select([r, t], %{x: r.x, category_id: t.id, depth: type(t.depth, :integer)})
      |> plan()

    assert all(query) ==
             ~s{WITH [tree] ([id], [depth]) AS (} <>
               ~s{SELECT c0.[id] AS [id], 1 AS [depth] FROM [categories] AS c0 WHERE (c0.[parent_id] IS NULL) } <>
               ~s{UNION ALL } <>
               ~s{(SELECT c0.[id], t1.[depth] + 1 FROM [categories] AS c0 } <>
               ~s{INNER JOIN [tree] AS t1 ON t1.[id] = c0.[parent_id])) } <>
               ~s{SELECT m0.[x], t1.[id], CAST(t1.[depth] AS bigint) } <>
               ~s{FROM [model] AS m0 } <>
               ~s{INNER JOIN [tree] AS t1 ON t1.[id] = m0.[category_id]}
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
             ~s{WITH [comments_scope] ([entity_id], [text]) AS (} <>
               ~s{SELECT c0.[entity_id] AS [entity_id], c0.[text] AS [text] } <>
               ~s{FROM [comments] AS c0 WHERE (c0.[deleted_at] IS NULL)) } <>
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
      Model
      |> recursive_ctes(true)
      |> with_cte("tree", as: fragment(@raw_sql_cte))
      |> join(:inner, [p], c in "tree", on: c.id == p.category_id)
      |> select([r], r.x)
      |> plan()

    assert_raise(
      Ecto.QueryError,
      ~r"Unfortunately Tds adapter does not support fragment in CTE",
      fn ->
        all(query)
      end
    )
  end

  test "CTE update_all" do
    cte_query =
      from(x in Model, order_by: [asc: :id], limit: 10, lock: "WITH(NOLOCK)", select: %{id: x.id})

    query =
      Model
      |> with_cte("target_rows", as: ^cte_query)
      |> join(:inner, [row], target in "target_rows", on: target.id == row.id)
      |> select([r, t], r)
      |> update(set: [x: 123])
      |> plan(:update_all)

    assert update_all(query) ==
      ~s{WITH [target_rows] ([id]) AS } <>
      ~s{(SELECT TOP(10) m0.[id] AS [id] FROM [model] AS m0 WITH(NOLOCK) ORDER BY m0.[id]) } <>
      ~s{UPDATE m0 } <>
      ~s{SET m0.[x] = 123 } <>
      ~s{OUTPUT INSERTED.[id], INSERTED.[x], INSERTED.[y], INSERTED.[z], INSERTED.[w] } <>
      ~s{FROM [model] AS m0 } <>
      ~s{INNER JOIN [target_rows] AS t1 ON t1.[id] = m0.[id]}
  end

  test "CTE delete_all" do
    cte_query =
      from(x in Model, order_by: [asc: :id], limit: 10, select: %{id: x.id})

    query =
      Model
      |> with_cte("target_rows", as: ^cte_query)
      |> join(:inner, [row], target in "target_rows", on: target.id == row.id)
      |> select([r, t], r)
      |> plan(:delete_all)

    assert delete_all(query) ==
      ~s{WITH [target_rows] ([id]) AS } <>
      ~s{(SELECT TOP(10) m0.[id] AS [id] FROM [model] AS m0 ORDER BY m0.[id]) } <>
      ~s{DELETE m0 } <>
      ~s{OUTPUT DELETED.[id], DELETED.[x], DELETED.[y], DELETED.[z], DELETED.[w] } <>
      ~s{FROM [model] AS m0 } <>
      ~s{INNER JOIN [target_rows] AS t1 ON t1.[id] = m0.[id]}
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> select([r], [r.x, r.y]) |> plan()
    assert all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> select([r], struct(r, [:x, :y])) |> plan()
    assert all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}
  end

  test "aggregates" do
    query = Model |> select([r], count(r.x)) |> plan()
    assert all(query) == ~s{SELECT count(m0.[x]) FROM [model] AS m0}

    query = Model |> select([r], count(r.x, :distinct)) |> plan()
    assert all(query) == ~s{SELECT count(DISTINCT m0.[x]) FROM [model] AS m0}

    query = Model |> select([r], count()) |> plan()
    assert all(query) == ~s{SELECT count(*) FROM [model] AS m0}
  end

  # test "aggregate filters" do
  #   query = Model |> select([r], count(r.x) |> filter(r.x > 10)) |> plan()
  #   assert all(query) == ~s{SELECT count(CASE WHEN m0.[x] > 10 THEN 1 ELSE NULL) FROM [model] AS m0}

  #   query = Model |> select([r], count(r.x) |> filter(r.x > 10 and r.x < 50)) |> plan()
  #   assert all(query) == ~s{SELECT count(CASE WHEN (m0.[x] > 10) AND (m.[x] < 50) THEN 1 ELSE NULL) FROM [schema] AS s0}

  #   query = Model |> select([r], count() |> filter(r.x > 10)) |> plan()
  #   assert all(query) == ~s{SELECT count(CASE WHEN m0.[x] > 10 THEN 1 ELSE NULL) FROM [model] AS m0}
  # end



  test "select with operation" do
    query = Model |> select([r], r.x * 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] * 2 FROM [model] AS m0}

    query = Model |> select([r], r.x / 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] / 2 FROM [model] AS m0}

    query = Model |> select([r], r.x + 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] + 2 FROM [model] AS m0}

    query = Model |> select([r], r.x - 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] - 2 FROM [model] AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    assert_raise Ecto.QueryError,
                 ~r"DISTINCT with multiple columns is not supported by MsSQL",
                 fn ->
                   query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> plan()
                   all(query)
                 end
  end

  test "where" do
    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> plan()

    assert all(query) ==
             ~s{SELECT m0.[x] FROM [model] AS m0 WHERE (m0.[x] = 42) AND (m0.[y] <> 43)}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x]}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y]}

    query = Model |> order_by([r], asc: r.x, desc: r.y) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y] DESC}

    query = Model |> order_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TOP(3) CAST(1 as bit) FROM [model] AS m0}

    query = Model |> order_by([r], r.x) |> offset([r], 5) |> select([], true) |> plan()

    assert_raise Ecto.QueryError, fn ->
      all(query)
    end

    query =
      Model |> order_by([r], r.x) |> offset([r], 5) |> limit([r], 3) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [model] AS m0 ORDER BY m0.[x] OFFSET 5 ROW FETCH NEXT 3 ROWS ONLY}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], true) |> plan()

    assert_raise Ecto.QueryError, fn ->
      all(query)
    end
  end

  test "lock" do
    query = Model |> lock("WITH(NOLOCK)") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [model] AS m0 WITH(NOLOCK)}
  end

  test "string escape" do
    query = "model" |> where(foo: "'\\  ") |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [model] AS m0 WHERE (m0.[foo] = CONVERT(nvarchar(4), 0x27005c0020002000))}

    query = "model" |> where(foo: "'") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [model] AS m0 WHERE (m0.[foo] = N'''')}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] = 2 FROM [model] AS m0}

    query = Model |> select([r], r.x != 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] <> 2 FROM [model] AS m0}

    query = Model |> select([r], r.x <= 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] <= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x >= 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] >= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x < 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] < 2 FROM [model] AS m0}

    query = Model |> select([r], r.x > 2) |> plan()
    assert all(query) == ~s{SELECT m0.[x] > 2 FROM [model] AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT m0.[x] IS NULL FROM [model] AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT NOT (m0.[x] IS NULL) FROM [model] AS m0}
  end

  test "fragments" do
    query =
      Model
      |> select([r], fragment("lower(?)", r.x))
      |> plan()

    assert all(query) == ~s{SELECT lower(m0.[x]) FROM [model] AS m0}

    value = 13
    query = Model |> select([r], fragment("lower(?)", ^value)) |> plan()
    assert all(query) == ~s{SELECT lower(@1) FROM [model] AS m0}

    query = Model |> select([], fragment(title: 2)) |> plan()

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

    query = "schema" |> where(foo: <<0,?a,?b,?c>>) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 0x00616263)}

    query = "schema" |> where(foo: 123) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT CAST(1 as bit) FROM [schema] AS s0 WHERE (s0.[foo] = 123.0)}
  end

  test "tagged type" do
    query =
      Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Tds.Types.UUID)) |> plan()

    assert all(query) == ~s{SELECT CAST(@1 AS uniqueidentifier) FROM [model] AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], (r.x > 0 and r.y > ^(-z)) or true) |> plan()
    assert all(query) == ~s{SELECT ((m0.[x] > 0) AND (m0.[y] > @1)) OR 1 FROM [model] AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> plan()
    assert all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

    query = Model |> select([e], 1 in [1, e.x, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,m0.[x],3) FROM [model] AS m0}

    query = Model |> select([e], 1 in ^[]) |> plan()
    # SelectExpr fields in Ecto v1 == [{:in, [], [1, []]}]
    # SelectExpr fields in Ecto v2 == [{:in, [], [1, {:^, [], [0, 0]}]}]
    assert all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

    query = Model |> select([e], 1 in ^[1, 2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (@1,@2,@3) FROM [model] AS m0}

    query = Model |> select([e], 1 in [1, ^2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,@1,3) FROM [model] AS m0}
  end

  test "in expression with multiple where conditions" do
    xs = [1, 2, 3]
    y = 4

    query =
      Model
      |> where([m], m.x in ^xs)
      |> where([m], m.y == ^y)
      |> select([m], m.x)

    assert all(query |> plan) ==
             ~s{SELECT m0.[x] FROM [model] AS m0 WHERE (m0.[x] IN (@1,@2,@3)) AND (m0.[y] = @4)}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([p], p.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x])}

    query =
      Model
      |> having([p], p.x == p.x)
      |> having([p], p.y == p.y)
      |> select([p], [p.y, p.x])
      |> plan()

    assert all(query) ==
             ~s{SELECT m0.[y], m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x]) AND (m0.[y] = m0.[y])}

    query = Model |> select([e], 1 in fragment("foo")) |> plan()
    assert all(query) == ~s{SELECT 1 IN (foo) FROM [model] AS m0}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x]}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY 2}

    query = Model3 |> group_by([r], 2) |> select([r], r.binary) |> plan()
    assert all(query) == ~s{SELECT m0.[binary] FROM [foo].[model3] AS m0 GROUP BY 2}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x], m0.[y]}

    query = Model |> group_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "interpolated values" do
    cte1 = "model1" |> select([m], %{id: m.id, smth: ^true}) |> where([], fragment("?", ^1))
    union = "model1" |> select([m], {m.id, ^true}) |> where([], fragment("?", ^5))
    union_all = "model2" |> select([m], {m.id, ^false}) |> where([], fragment("?", ^6))

    query = "model"
      |> with_cte("cte1", as: ^cte1)
      |> select([m], {m.id, ^true})
      |> join(:inner, [], Model2, on: fragment("?", ^true))
      |> join(:inner, [], Model2, on: fragment("?", ^false))
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
      ~s{WITH [cte1] ([id], [smth]) AS } <>
      ~s{(SELECT m0.[id] AS [id], @1 AS [smth] FROM [model1] AS m0 WHERE (@2)) } <>
      ~s{SELECT m0.[id], @3 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON @4 } <>
      ~s{INNER JOIN [model2] AS m2 ON @5 } <>
      ~s{WHERE (@6) AND (@7) } <>
      ~s{GROUP BY @8, @9 HAVING (@10) AND (@11) } <>
      ~s{UNION (SELECT m0.[id], @12 FROM [model1] AS m0 WHERE (@13)) } <>
      ~s{UNION ALL (SELECT m0.[id], @14 FROM [model2] AS m0 WHERE (@15)) } <>
      ~s{ORDER BY @16 OFFSET @18 ROW FETCH NEXT @17 ROWS ONLY}

    assert all(query) == String.trim_trailing(result)
  end

  # ## *_all

  test "update all" do
    query = from(m in Model, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0}

    query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = m0.[y] + 1, m0.[z] = m0.[z] + -3 FROM [model] AS m0}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]]) |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

    # TODO:
    # nvarchar(max) conversion

    query = from(m in Model, update: [set: [x: 0, y: 123]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = 123 FROM [model] AS m0}

    query = from(m in Model, update: [set: [x: ^0]]) |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE m0 SET m0.[x] = @1 FROM [model] AS m0}

    query =
      Model
      |> join(:inner, [p], q in Model2, on: p.x == q.z)
      |> update([_], set: [x: 0])
      |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

    query =
      from(
        e in Model,
        where: e.x == 123,
        update: [set: [x: 0]],
        join: q in Model2,
        on: e.x == q.z
      )
      |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 } <>
               ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  end

  test "update all with prefix" do
    query =
      from(m in Model, update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)

    assert update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [prefix].[model] AS m0}
  end

  test "delete all" do
    query = Model |> Queryable.to_query() |> plan()
    assert delete_all(query) == ~s{DELETE m0 FROM [model] AS m0}

    query = from(e in Model, where: e.x == 123) |> plan()
    assert delete_all(query) == ~s{DELETE m0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

    query = Model |> join(:inner, [p], q in Model2, on: p.x == q.z) |> plan()

    assert delete_all(query) ==
             ~s{DELETE m0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

    query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> plan()

    assert delete_all(query) ==
             ~s{DELETE m0 FROM [model] AS m0 } <>
               ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  end

  test "delete all with prefix" do
    query = Model |> Queryable.to_query() |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE m0 FROM [prefix].[model] AS m0}

    query = Model |> from(prefix: "first") |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE m0 FROM [first].[model] AS m0}
  end

  # ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, on: p.x == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

    query =
      Model
      |> join(:inner, [p], q in Model2, on: p.x == q.z)
      |> join(:inner, [], Model, on: true)
      |> select([], true)
      |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] } <>
               ~s{INNER JOIN [model] AS m2 ON 1 = 1 }
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, on: q.z == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m1.[z]}
  end

  test "join without model" do
    query =
      "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], true) |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [posts] AS p0 INNER JOIN [comments] AS c1 ON p0.[x] = c1.[z]}
  end

  test "join with prefix" do
    query =
      Model
      |> join(:inner, [p], q in Model2, on: p.x == q.z)
      |> Map.put(:prefix, "prefix")
      |> select([], true)
      |> plan()

    assert all(query) ==
             ~s{SELECT CAST(1 as bit) FROM [prefix].[model] AS m0 INNER JOIN [prefix].[model2] AS m1 ON m0.[x] = m1.[z]}
  end

  test "join with fragment" do
    query =
      Model
      |> join(
        :inner,
        [p],
        q in fragment("SELECT * FROM model2 AS m2 WHERE m2.id = ? AND m2.field = ?", p.x, ^10)
      )
      |> select([p], {p.id, ^0})
      |> where([p], p.id > 0 and p.id < ^100)
      |> plan()

    assert all(query) ==
             ~s{SELECT m0.[id], @1 FROM [model] AS m0 INNER JOIN } <>
               ~s{(SELECT * FROM model2 AS m2 WHERE m2.id = m0.[x] AND m2.field = @2) AS f1 ON 1 = 1 } <>
               ~s{ WHERE ((m0.[id] > 0) AND (m0.[id] < @3))}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [model2] AS m0 INNER JOIN [model] AS m1 ON m1.[x] = m0.[z]"
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m0.[x]"
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> plan()

    assert all(query) ==
             "SELECT CAST(1 as bit) FROM [model] AS m0 INNER JOIN [foo].[model3] AS m1 ON m1.[id] = m0.[y]"
  end

  test "join produces correct bindings" do
    query = from(p in Model, join: c in Model2, on: true)
    query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
    query = plan(query)

    assert all(query) ==
             "SELECT m0.[id], m2.[id] FROM [model] AS m0 INNER JOIN [model2] AS m1 ON 1 = 1  INNER JOIN [model2] AS m2 ON 1 = 1 "
  end

  # # Model based

  test "insert" do
    # prefx, table, header, rows, on_conflict, returning
    query = insert(nil, "model", [:x, :y], [[:x, :y]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO [model] ([x], [y]) OUTPUT INSERTED.[id] VALUES (@1, @2)}

    query = insert(nil, "model", [:x, :y], [[:x, :y], [nil, :y]], {:raise, [], []}, [:id])

    assert query ==
             ~s{INSERT INTO [model] ([x], [y]) OUTPUT INSERTED.[id] VALUES (@1, @2),(DEFAULT, @3)}

    query = insert(nil, "model", [], [[]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO [model] OUTPUT INSERTED.[id] DEFAULT VALUES}

    query = insert("prefix", "model", [], [[]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO [prefix].[model] OUTPUT INSERTED.[id] DEFAULT VALUES}
  end

  test "update" do
    query = update(nil, "model", [:id], [:x, :y], [])
    assert query == ~s{UPDATE [model] SET [id] = @1 WHERE [x] = @2 AND [y] = @3}

    query = update(nil, "model", [:x, :y], [:id], [:z])
    assert query == ~s{UPDATE [model] SET [x] = @1, [y] = @2 OUTPUT INSERTED.[z] WHERE [id] = @3}

    query = update("prefix", "model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE [prefix].[model] SET [x] = @1, [y] = @2 WHERE [id] = @3}
  end

  test "delete" do
    query = delete(nil, "model", [:x, :y], [])
    assert query == ~s{DELETE FROM [model] WHERE [x] = @1 AND [y] = @2}

    query = delete(nil, "model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM [model] OUTPUT DELETED.[z] WHERE [x] = @1 AND [y] = @2}

    query = delete("prefix", "model", [:x, :y], [])
    assert query == ~s{DELETE FROM [prefix].[model] WHERE [x] = @1 AND [y] = @2}
  end

  # # DDL

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "create table" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :bigserial, [primary_key: true]},
         {:add, :title, :string, []},
         {:add, :created_at, :datetime, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [posts] ([id] bigint IDENTITY(1,1), [title] nvarchar(255), [created_at] datetime,
             CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
             """
             |> remove_newlines
           ]
  end

  test "create table with prefix" do
    create =
      {:create, table(:posts, prefix: :foo),
       [
         {:add, :name, :string, [default: "Untitled", size: 20, null: false]},
         {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
         {:add, :on_hand, :integer, [default: 0, null: true]},
         {:add, :is_active, :boolean, [default: true]}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [foo].[posts]
             ([name] nvarchar(20) NOT NULL CONSTRAINT [DF_foo_posts_name] DEFAULT (N'Untitled'),
             [price] numeric(8,2) CONSTRAINT [DF_foo_posts_price] DEFAULT (expr),
             [on_hand] integer NULL CONSTRAINT [DF_foo_posts_on_hand] DEFAULT (0),
             [is_active] bit CONSTRAINT [DF_foo_posts_is_active] DEFAULT (1))
             """
             |> remove_newlines
           ]
  end

  test "create table with reference" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories}, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT,
             CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id])
             REFERENCES [categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION,
             CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
             """
             |> remove_newlines
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
             CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([a], [b]))
             """
             |> remove_newlines
           ]
  end

  test "create table with named reference" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, name: :foo_bar}, []}
       ]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT,
               CONSTRAINT [foo_bar] FOREIGN KEY ([category_id]) REFERENCES [categories]([id])
               ON DELETE NO ACTION ON UPDATE NO ACTION,
               CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
               """
               |> remove_newlines
             ]
  end

  test "create table with reference and on_delete: :nothing clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :bigserial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :nothing}, []}
       ]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts] ([id] bigint IDENTITY(1,1), [category_id] BIGINT,
               CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id])
               REFERENCES [categories]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION, CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
               """
               |> remove_newlines
             ]
  end

  test "create table with reference and on_delete: :nilify_all clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :nilify_all}, []}
       ]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT,
               CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id])
               REFERENCES [categories]([id]) ON DELETE SET NULL ON UPDATE NO ACTION,
               CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
               """
               |> remove_newlines
             ]
  end

  test "create table with reference and on_delete: :delete_all clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :delete_all}, []}
       ]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT,
               CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id])
               REFERENCES [categories]([id]) ON DELETE CASCADE ON UPDATE NO ACTION,
               CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id]))
               """
               |> remove_newlines
             ]
  end

  test "create table with column options" do
    create =
      {:create, table(:posts),
       [
         {:add, :name, :string, [default: "Untitled", size: 20, null: false]},
         {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
         {:add, :on_hand, :integer, [default: 0, null: true]},
         {:add, :is_active, :boolean, [default: true]}
       ]}

    assert execute_ddl(create) ==
             [
               """
               CREATE TABLE [posts]
               ([name] nvarchar(20) NOT NULL CONSTRAINT [DF__posts_name] DEFAULT (N'Untitled'),
               [price] numeric(8,2) CONSTRAINT [DF__posts_price] DEFAULT (expr),
               [on_hand] integer NULL CONSTRAINT [DF__posts_on_hand] DEFAULT (0),
               [is_active] bit CONSTRAINT [DF__posts_is_active] DEFAULT (1))
               """
               |> remove_newlines
             ]
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert execute_ddl(drop) == ["DROP TABLE [posts]"]
  end

  test "drop table with prefixes" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert execute_ddl(drop) == ["DROP TABLE [foo].[posts]"]
  end

  test "alter table" do
    alter =
      {:alter, table(:posts),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:modify, :price, :numeric, [precision: 8, scale: 2]},
         {:remove, :summary}
       ]}

    assert execute_ddl(alter) ==
             [
               """
               ALTER TABLE [posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF__posts_title] DEFAULT (N'Untitled');
               IF (OBJECT_ID(N'[DF__posts_price]', 'D') IS NOT NULL) BEGIN ALTER TABLE [posts] DROP CONSTRAINT [DF__posts_price];  END;
               ALTER TABLE [posts] ALTER COLUMN [price] numeric(8,2);
               ALTER TABLE [posts] DROP COLUMN [summary];
               """
               |> remove_newlines
               |> Kernel.<>(" ")
             ]
  end

  test "alter table with prefix" do
    alter =
      {:alter, table(:posts, prefix: :foo),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:add, :author_id, %Reference{table: :author}, []},
         {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
         {:modify, :cost, :integer, [null: true, default: nil]},
         {:modify, :permalink_id, %Reference{table: :permalinks, prefix: :foo}, null: false},
         {:remove, :summary}
       ]}

    expected_ddl = [
      """
      ALTER TABLE [foo].[posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF_foo_posts_title] DEFAULT (N'Untitled');
      ALTER TABLE [foo].[posts] ADD [author_id] BIGINT;
      ALTER TABLE [foo].[posts] ADD CONSTRAINT [posts_author_id_fkey] FOREIGN KEY ([author_id]) REFERENCES [foo].[author]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
      IF (OBJECT_ID(N'[DF_foo_posts_price]', 'D') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_foo_posts_price];  END;
      ALTER TABLE [foo].[posts] ALTER COLUMN [price] numeric(8,2) NULL;
      IF (OBJECT_ID(N'[DF_foo_posts_cost]', 'D') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_foo_posts_cost];  END;
      ALTER TABLE [foo].[posts] ALTER COLUMN [cost] integer NULL;
      ALTER TABLE [foo].[posts] ADD CONSTRAINT [DF_foo_posts_cost] DEFAULT (NULL) FOR [cost];
      IF (OBJECT_ID(N'[posts_permalink_id_fkey]', 'F') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [posts_permalink_id_fkey];  END;
      ALTER TABLE [foo].[posts] ALTER COLUMN [permalink_id] BIGINT NOT NULL;
      ALTER TABLE [foo].[posts] ADD CONSTRAINT [posts_permalink_id_fkey] FOREIGN KEY ([permalink_id]) REFERENCES [foo].[permalinks]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
      ALTER TABLE [foo].[posts] DROP COLUMN [summary];
      """
      |> remove_newlines
      |> Kernel.<>(" ")
    ]

    assert execute_ddl(alter) == expected_ddl
  end

  test "alter table with reference" do
    alter = {:alter, table(:posts), [{:add, :comment_id, %Reference{table: :comments}, []}]}

    assert execute_ddl(alter) ==
             [
               """
               ALTER TABLE [posts] ADD [comment_id] BIGINT;
               ALTER TABLE [posts] ADD CONSTRAINT [posts_comment_id_fkey] FOREIGN KEY ([comment_id]) REFERENCES [comments]([id])
               ON DELETE NO ACTION ON UPDATE NO ACTION;
               """
               |> remove_newlines
               |> Kernel.<>(" ")
             ]
  end

  test "alter table with adding foreign key constraint" do
    alter =
      {:alter, table(:posts),
       [
         {:modify, :user_id, %Reference{table: :users, on_delete: :delete_all, type: :bigserial},
          []}
       ]}

    assert execute_ddl(alter) ==
             [
               """
               IF (OBJECT_ID(N'[posts_user_id_fkey]', 'F') IS NOT NULL) BEGIN ALTER TABLE [posts] DROP CONSTRAINT [posts_user_id_fkey];  END;
               ALTER TABLE [posts] ALTER COLUMN [user_id] BIGINT;
               ALTER TABLE [posts] ADD CONSTRAINT [posts_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [users]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
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
               CONSTRAINT [posts_pkey] PRIMARY KEY CLUSTERED ([id])) WITH FOO=BAR
               """
               |> remove_newlines
             ]
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

    # below should be handled with collation on column which is indexed

    # create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    # assert execute_ddl(create) ==
    #        ~s|CREATE INDEX [posts$main] ON [posts] ([lower(permalink)])|

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

    assert_raise ArgumentError, ~r"MSSQL does not support using in indexes.", fn ->
      execute_ddl(create)
    end
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert execute_ddl(drop) == [~s|DROP INDEX [posts$main] ON [posts];|]
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo)}

    assert execute_ddl(drop) ==
             [~s|DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts];|]
  end

  test "drop index with prefix if exists" do
    drop =
      {:drop_if_exists,
       index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo)}

    assert execute_ddl(drop) ==
             [
               """
               IF EXISTS (SELECT name FROM sys.indexes
               WHERE name = N'posts_category_id_permalink_index'
               AND object_id = OBJECT_ID(N'foo.posts'))
               DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts];
               """
               |> remove_newlines
             ]
  end

  test "drop index asserting concurrency" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert execute_ddl(drop) == [~s|DROP INDEX [posts$main] ON [posts] LOCK=NONE;|]
  end

  defp remove_newlines(string) do
    string |> String.trim() |> String.replace("\n", " ")
  end
end
