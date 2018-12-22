defmodule Ecto.Adapters.MsSqlTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.MsSql.Connection, as: SQL
  alias Ecto.Migration.Reference

  defmodule Model do
    use Ecto.Schema

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, :decimal

      has_many :comments, Ecto.Adapters.MsSqlTest.Model2,
        references: :x,
        foreign_key: :z

      has_one :permalink, Ecto.Adapters.MsSqlTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Schema

    import Ecto.Query

    schema "model2" do
      belongs_to :post, Ecto.Adapters.MsSqlTest.Model,
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
    {query, _params} = Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.MySQL, query)
    query
  end

  test "from" do
    query = Model |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "from Model3 with schema foo" do
    query = Model3 |> select([r], r.binary) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[binary] FROM [foo].[model3] AS m0}
  end

  test "from without model" do
    query = "model" |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}

    # todo: somthing is changed into ecto causing this exception to be missed.
    # instead query is built as "SELECT &(0) FROM [posts] AS p0" which won't work
    assert_raise Ecto.QueryError,
                 ~r"TDS Adapter does not support selecting all fields from",
                 fn ->
                   query = from(p in "posts", select: [p]) |> plan()

                   SQL.all(query)
                   |> IO.inspect()
                 end
  end

  test "subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: p.id == c.post_id) |> select([_, p], p.x) |> plan
    assert SQL.all(query) ==
            ~s{SELECT s1.[x] FROM [comments] AS c0 } <>
            ~s{INNER JOIN (SELECT p0.[x] AS [x], p0.[y] AS [y] FROM [posts] AS p0 WHERE (p0.[title] = @1)) AS s1 ON s1.[id] = c0.[post_id]}

    # query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan

    # assert SQL.all(query) ==
    #          ~s{SELECT s0.[x], s0.[z] FROM (SELECT p0.[x] AS [x], p0.[y] AS [z] FROM [posts] AS p0) AS s0}
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> select([r], [r.x, r.y]) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}
  end

  test "select with operation" do
    query = Model |> select([r], r.x * 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] * 2 FROM [model] AS m0}

    query = Model |> select([r], r.x / 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] / 2 FROM [model] AS m0}

    query = Model |> select([r], r.x + 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] + 2 FROM [model] AS m0}

    query = Model |> select([r], r.x - 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] - 2 FROM [model] AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> plan
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(true) |> select([r], {r.x, r.y}) |> plan
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(false) |> select([r], {r.x, r.y}) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    assert_raise Ecto.QueryError, ~r"MSSQL does not allow expressions in distinct", fn ->
      query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> plan
      SQL.all(query)
    end
  end

  test "where" do
    query =
      Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> plan

    assert SQL.all(query) ==
             ~s{SELECT m0.[x] FROM [model] AS m0 WHERE (m0.[x] = 42) AND (m0.[y] <> 43)}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x]}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y]}

    query = Model |> order_by([r], asc: r.x, desc: r.y) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y] DESC}

    query = Model |> order_by([r], []) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], 0) |> plan
    assert SQL.all(query) == ~s{SELECT TOP(3) 0 FROM [model] AS m0}

    query = Model |> order_by([r], r.x) |> offset([r], 5) |> select([], 0) |> plan

    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end

    query =
      Model |> order_by([r], r.x) |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [model] AS m0 ORDER BY m0.[x] OFFSET 5 ROW FETCH NEXT 3 ROWS ONLY}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> plan

    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end
  end

  test "lock" do
    query = Model |> lock("WITH(NOLOCK)") |> select([], 0) |> plan
    assert SQL.all(query) == ~s{SELECT 0 FROM [model] AS m0 WITH(NOLOCK)}
  end

  test "string escape" do
    query = Model |> select([], "'\\  ") |> plan

    assert SQL.all(query) ==
             ~s{SELECT CONVERT(nvarchar(4), 0x27005c0020002000) FROM [model] AS m0}

    query = Model |> select([], "'") |> plan
    assert SQL.all(query) == ~s{SELECT N'''' FROM [model] AS m0}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] = 2 FROM [model] AS m0}

    query = Model |> select([r], r.x != 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] <> 2 FROM [model] AS m0}

    query = Model |> select([r], r.x <= 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] <= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x >= 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] >= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x < 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] < 2 FROM [model] AS m0}

    query = Model |> select([r], r.x > 2) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] > 2 FROM [model] AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] IS NULL FROM [model] AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> plan
    assert SQL.all(query) == ~s{SELECT NOT (m0.[x] IS NULL) FROM [model] AS m0}
  end

  test "fragments" do
    query =
      Model
      |> select([r], fragment("lower(?)", r.x))
      |> plan

    assert SQL.all(query) == ~s{SELECT lower(m0.[x]) FROM [model] AS m0}

    value = 13
    query = Model |> select([r], fragment("lower(?)", ^value)) |> plan
    assert SQL.all(query) == ~s{SELECT lower(@1) FROM [model] AS m0}

    query = Model |> select([], fragment(title: 2)) |> plan

    assert_raise Ecto.QueryError,
                 ~r"TDS adapter does not support keyword or interpolated fragments",
                 fn ->
                   SQL.all(query)
                 end
  end

  test "literals" do
    query = Model |> select([], nil) |> plan
    assert SQL.all(query) == ~s{SELECT NULL FROM [model] AS m0}

    query = Model |> select([], true) |> plan
    assert SQL.all(query) == ~s{SELECT 1 FROM [model] AS m0}

    query = Model |> select([], false) |> plan
    assert SQL.all(query) == ~s{SELECT 0 FROM [model] AS m0}

    query = Model |> select([], "abc") |> plan
    assert SQL.all(query) == ~s{SELECT N'abc' FROM [model] AS m0}

    query = Model |> select([], 123) |> plan
    assert SQL.all(query) == ~s{SELECT 123 FROM [model] AS m0}

    query = Model |> select([], 123.0) |> plan
    assert SQL.all(query) == ~s{SELECT 123.0 FROM [model] AS m0}
  end

  test "tagged type" do
    query =
      Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Tds.Types.UUID)) |> plan

    assert SQL.all(query) == ~s{SELECT CAST(@1 AS uniqueidentifier) FROM [model] AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], (r.x > 0 and r.y > ^(-z)) or true) |> plan
    assert SQL.all(query) == ~s{SELECT ((m0.[x] > 0) AND (m0.[y] > @1)) OR 1 FROM [model] AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> plan
    assert SQL.all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

    query = Model |> select([e], 1 in [1, e.x, 3]) |> plan
    assert SQL.all(query) == ~s{SELECT 1 IN (1,m0.[x],3) FROM [model] AS m0}

    query = Model |> select([e], 1 in ^[]) |> plan
    # SelectExpr fields in Ecto v1 == [{:in, [], [1, []]}]
    # SelectExpr fields in Ecto v2 == [{:in, [], [1, {:^, [], [0, 0]}]}]
    assert SQL.all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

    query = Model |> select([e], 1 in ^[1, 2, 3]) |> plan
    assert SQL.all(query) == ~s{SELECT 1 IN (@1,@2,@3) FROM [model] AS m0}

    query = Model |> select([e], 1 in [1, ^2, 3]) |> plan
    assert SQL.all(query) == ~s{SELECT 1 IN (1,@1,3) FROM [model] AS m0}
  end

  test "in expression with multiple where conditions" do
    xs = [1, 2, 3]
    y = 4

    query =
      Model
      |> where([m], m.x in ^xs)
      |> where([m], m.y == ^y)
      |> select([m], m.x)

    assert SQL.all(query |> plan) ==
             ~s{SELECT m0.[x] FROM [model] AS m0 WHERE (m0.[x] IN (@1,@2,@3)) AND (m0.[y] = @4)}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([p], p.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x])}

    query =
      Model
      |> having([p], p.x == p.x)
      |> having([p], p.y == p.y)
      |> select([p], [p.y, p.x])
      |> plan

    assert SQL.all(query) ==
             ~s{SELECT m0.[y], m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x]) AND (m0.[y] = m0.[y])}

    query = Model |> select([e], 1 in fragment("foo")) |> plan
    assert SQL.all(query) == ~s{SELECT 1 IN (foo) FROM [model] AS m0}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x]}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY 2}

    query = Model3 |> group_by([r], 2) |> select([r], r.binary) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[binary] FROM [foo].[model3] AS m0 GROUP BY 2}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x], m0.[y]}

    query = Model |> group_by([r], []) |> select([r], r.x) |> plan
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "interpolated values" do
    query =
      Model
      |> select([m], {m.id, ^0})
      |> join(:inner, [], Model3, on: fragment("?", ^true))
      |> join(:inner, [], Model3, on: fragment("?", ^false))
      |> where([], fragment("?", ^true))
      |> where([], fragment("?", ^false))
      |> having([], fragment("?", ^true))
      |> having([], fragment("?", ^false))
      |> group_by([], fragment("?", ^1))
      |> group_by([], fragment("?", ^2))
      |> order_by([], fragment("?", ^3))
      |> order_by([], ^:x)
      |> limit([], ^4)
      |> offset([], ^5)
      |> plan

    result =
      "SELECT m0.[id], @1 FROM [model] AS m0 INNER JOIN [foo].[model3] AS m1 ON @2 " <>
        "INNER JOIN [foo].[model3] AS m2 ON @3 WHERE (@4) AND (@5) " <>
        "GROUP BY @6, @7 HAVING (@8) AND (@9) " <>
        "ORDER BY @10, m0.[x] OFFSET @12 ROW FETCH NEXT @11 ROWS ONLY"

    assert SQL.all(query) == String.trim_trailing(result)
  end

  # ## *_all

  test "update all" do
    query = from(m in Model, update: [set: [x: 0]]) |> plan(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0}

    query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> plan(:update_all)

    assert SQL.update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = m0.[y] + 1, m0.[z] = m0.[z] + -3 FROM [model] AS m0}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]]) |> plan(:update_all)

    assert SQL.update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

    # TODO:
    # nvarchar(max) conversion

    query = from(m in Model, update: [set: [x: 0, y: 123]]) |> plan(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = 123 FROM [model] AS m0}

    query = from(m in Model, update: [set: [x: ^0]]) |> plan(:update_all)
    assert SQL.update_all(query) == ~s{UPDATE m0 SET m0.[x] = @1 FROM [model] AS m0}

    query =
      Model
      |> join(:inner, [p], q in Model2, on: p.x == q.z)
      |> update([_], set: [x: 0])
      |> plan(:update_all)

    assert SQL.update_all(query) ==
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

    assert SQL.update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 } <>
               ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  end

  test "update all with prefix" do
    query = from(m in Model, update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)

    assert SQL.update_all(query) ==
             ~s{UPDATE m0 SET m0.[x] = 0 FROM [prefix].[model] AS m0}
  end

  test "delete all" do
    query = Model |> Queryable.to_query() |> plan
    assert SQL.delete_all(query) == ~s{DELETE m0 FROM [model] AS m0}

    query = from(e in Model, where: e.x == 123) |> plan
    assert SQL.delete_all(query) == ~s{DELETE m0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

    query = Model |> join(:inner, [p], q in Model2, on: p.x == q.z) |> plan

    assert SQL.delete_all(query) ==
             ~s{DELETE m0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

    query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> plan

    assert SQL.delete_all(query) ==
             ~s{DELETE m0 FROM [model] AS m0 } <>
               ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  end

  test "delete all with prefix" do
    query = Model |> Queryable.to_query() |> Map.put(:prefix, "prefix") |> plan
    assert SQL.delete_all(query) == ~s{DELETE m0 FROM [prefix].[model] AS m0}

    query = Model |> from(prefix: "first") |> Map.put(:prefix, "prefix") |> plan
    assert SQL.delete_all(query) == ~s{DELETE m0 FROM [first].[model] AS m0}
  end

  # ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, on: p.x == q.z) |> select([], 0) |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

    query =
      Model
      |> join(:inner, [p], q in Model2, on: p.x == q.z)
      |> join(:inner, [], Model, on: true)
      |> select([], 0)
      |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] } <>
               ~s{INNER JOIN [model] AS m2 ON 1}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, on: q.z == q.z) |> select([], 0) |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m1.[z]}
  end

  test "join without model" do
    query =
      "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], 0) |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [posts] AS p0 INNER JOIN [comments] AS c1 ON p0.[x] = c1.[z]}
  end

  test "join with prefix" do
    query = Model |> join(:inner, [p], q in Model2, on: p.x == q.z) |> Map.put(:prefix, "prefix") |> select([], 0) |> plan

    assert SQL.all(query) ==
             ~s{SELECT 0 FROM [prefix].[model] AS m0 INNER JOIN [prefix].[model2] AS m1 ON m0.[x] = m1.[z]}
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
      |> plan

    assert SQL.all(query) ==
             ~s{SELECT m0.[id], @1 FROM [model] AS m0 INNER JOIN } <>
               ~s{(SELECT * FROM model2 AS m2 WHERE m2.id = m0.[x] AND m2.field = @2) AS f1 ON 1 } <>
               ~s{WHERE ((m0.[id] > 0) AND (m0.[id] < @3))}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], 0) |> plan

    assert SQL.all(query) ==
             "SELECT 0 FROM [model2] AS m0 INNER JOIN [model] AS m1 ON m1.[x] = m0.[z]"
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], 0) |> plan

    assert SQL.all(query) ==
             "SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m0.[x]"
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], 0) |> plan

    assert SQL.all(query) ==
             "SELECT 0 FROM [model] AS m0 INNER JOIN [foo].[model3] AS m1 ON m1.[id] = m0.[y]"
  end

  test "join produces correct bindings" do
    query = from(p in Model, join: c in Model2, on: true)
    query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
    query = plan(query)

    assert SQL.all(query) ==
             "SELECT m0.[id], m2.[id] FROM [model] AS m0 INNER JOIN [model2] AS m1 ON 1 INNER JOIN [model2] AS m2 ON 1"
  end

  # # Model based

  test "insert" do
    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO [model] ([x], [y]) VALUES (@1, @2)}

    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y], [nil, :y]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO [model] ([x], [y]) VALUES (@1, @2),(DEFAULT, @3)}

    query = SQL.insert(nil, "model", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO [model] DEFAULT VALUES}

    query = SQL.insert("prefix", "model", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO [prefix].[model] DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update(nil, "model", [:id], [:x, :y], [])
    assert query == ~s{UPDATE [model] SET [id] = @1 WHERE [x] = @2 AND [y] = @3}

    query = SQL.update(nil, "model", [:x, :y], [:id], [:z])
    assert query == ~s{UPDATE [model] SET [x] = @1, [y] = @2 OUTPUT INSERTED.[z] WHERE [id] = @3}

    query = SQL.update("prefix", "model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE [prefix].[model] SET [x] = @1, [y] = @2 WHERE [id] = @3}
  end

  test "delete" do
    query = SQL.delete(nil, "model", [:x, :y], [])
    assert query == ~s{DELETE FROM [model] WHERE [x] = @1 AND [y] = @2}

    query = SQL.delete(nil, "model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM [model] OUTPUT DELETED.[z] WHERE [x] = @1 AND [y] = @2}

    query = SQL.delete("prefix", "model", [:x, :y], [])
    assert query == ~s{DELETE FROM [prefix].[model] WHERE [x] = @1 AND [y] = @2}
  end

  # # DDL

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3]

  test "executing a string during migration" do
    assert SQL.execute_ddl("example") == ["example"]
  end

  test "create table" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :bigserial, [primary_key: true]},
         {:add, :title, :string, []},
         {:add, :created_at, :datetime, []}
       ]}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE TABLE [posts] ([id] bigint IDENTITY(1,1), [title] nvarchar(255), [created_at] datetime, CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))|
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

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [foo].[posts] (",
               "[name] nvarchar(20) NOT NULL CONSTRAINT [DF_foo_posts_name] DEFAULT (N'Untitled'), ",
               "[price] numeric(8,2) CONSTRAINT [DF_foo_posts_price] DEFAULT (expr), ",
               "[on_hand] integer NULL CONSTRAINT [DF_foo_posts_on_hand] DEFAULT (0), ",
               "[is_active] bit CONSTRAINT [DF_foo_posts_is_active] DEFAULT (1)",
               ")"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with reference" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories}, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT, ",
               "CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id]) ",
               "REFERENCES [categories]([id]), CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with composite key" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :integer, [primary_key: true]},
         {:add, :b, :integer, [primary_key: true]},
         {:add, :name, :string, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([a] integer, [b] integer, [name] nvarchar(255), ",
               "CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([a], [b]))"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with named reference" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, name: :foo_bar}, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT, ",
               "CONSTRAINT [foo_bar] FOREIGN KEY ([category_id]) REFERENCES [categories]([id]), ",
               "CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with reference and on_delete: :nothing clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :bigserial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :nothing}, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([id] bigint IDENTITY(1,1), [category_id] BIGINT, ",
               "CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id]) ",
               "REFERENCES [categories]([id]), CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with reference and on_delete: :nilify_all clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :nilify_all}, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT, ",
               "CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id]) ",
               "REFERENCES [categories]([id]) ON DELETE SET NULL, ",
               "CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))"
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with reference and on_delete: :delete_all clause" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_id, %Reference{table: :categories, on_delete: :delete_all}, []}
       ]}

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] ([id] int IDENTITY(1,1), [category_id] BIGINT, ",
               "CONSTRAINT [posts_category_id_fkey] FOREIGN KEY ([category_id]) ",
               "REFERENCES [categories]([id]) ON DELETE CASCADE, ",
               "CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id]))"
             ]
             |> IO.iodata_to_binary()
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

    assert SQL.execute_ddl(create) ==
             [
               "CREATE TABLE [posts] (",
               "[name] nvarchar(20) NOT NULL CONSTRAINT [DF__posts_name] DEFAULT (N'Untitled'), ",
               "[price] numeric(8,2) CONSTRAINT [DF__posts_price] DEFAULT (expr), ",
               "[on_hand] integer NULL CONSTRAINT [DF__posts_on_hand] DEFAULT (0), ",
               "[is_active] bit CONSTRAINT [DF__posts_is_active] DEFAULT (1)",
               ")"
             ]
             |> IO.iodata_to_binary()
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE [posts]|
  end

  test "drop table with prefixes" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE [foo].[posts]|
  end

  test "alter table" do
    alter =
      {:alter, table(:posts),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:modify, :price, :numeric, [precision: 8, scale: 2]},
         {:remove, :summary}
       ]}

    assert SQL.execute_ddl(alter) ==
             [
               "ALTER TABLE [posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF__posts_title] DEFAULT (N'Untitled');",
               "IF (OBJECT_ID(N'[DF__posts_price]', 'D') IS NOT NULL) BEGIN ALTER TABLE [posts] DROP CONSTRAINT [DF__posts_price];  END;",
               "ALTER TABLE [posts] ALTER COLUMN [price] numeric(8,2);",
               "ALTER TABLE [posts] DROP COLUMN [summary];"
             ]
             |> Enum.map(&"#{&1} ")
             |> IO.iodata_to_binary()
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

    expected_ddl =
      [
        "ALTER TABLE [foo].[posts] ADD [title] nvarchar(100) NOT NULL CONSTRAINT [DF_foo_posts_title] DEFAULT (N'Untitled'); ",
        "ALTER TABLE [foo].[posts] ADD [author_id] BIGINT; ",
        "ALTER TABLE [foo].[posts] ADD CONSTRAINT [posts_author_id_fkey] FOREIGN KEY ([author_id]) REFERENCES [foo].[author]([id]); ",
        "IF (OBJECT_ID(N'[DF_foo_posts_price]', 'D') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_foo_posts_price];  END; ",
        "ALTER TABLE [foo].[posts] ALTER COLUMN [price] numeric(8,2) NULL; ",
        "IF (OBJECT_ID(N'[DF_foo_posts_cost]', 'D') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_foo_posts_cost];  END; ",
        "ALTER TABLE [foo].[posts] ALTER COLUMN [cost] integer NULL; ",
        "ALTER TABLE [foo].[posts] ADD CONSTRAINT [DF_foo_posts_cost] DEFAULT (NULL) FOR [cost]; ",
        "IF (OBJECT_ID(N'[posts_permalink_id_fkey]', 'F') IS NOT NULL) BEGIN ALTER TABLE [foo].[posts] DROP CONSTRAINT [posts_permalink_id_fkey];  END; ",
        "ALTER TABLE [foo].[posts] ALTER COLUMN [permalink_id] BIGINT NOT NULL; ",
        "ALTER TABLE [foo].[posts] ADD CONSTRAINT [posts_permalink_id_fkey] FOREIGN KEY ([permalink_id]) REFERENCES [foo].[permalinks]([id]); ",
        "ALTER TABLE [foo].[posts] DROP COLUMN [summary]; "
      ]
      |> IO.iodata_to_binary()

    assert SQL.execute_ddl(alter) == expected_ddl
  end

  test "alter table with reference" do
    alter = {:alter, table(:posts), [{:add, :comment_id, %Reference{table: :comments}, []}]}

    assert SQL.execute_ddl(alter) ==
             [
               "ALTER TABLE [posts] ADD [comment_id] BIGINT; ",
               "ALTER TABLE [posts] ADD CONSTRAINT [posts_comment_id_fkey] FOREIGN KEY ([comment_id]) REFERENCES [comments]([id]); "
             ]
             |> IO.iodata_to_binary()
  end

  test "alter table with adding foreign key constraint" do
    alter =
      {:alter, table(:posts),
       [{:modify, :user_id, %Reference{table: :users, on_delete: :delete_all, type: :bigserial}, []}]}

    assert SQL.execute_ddl(alter) ==
             [
               "IF (OBJECT_ID(N'[posts_user_id_fkey]', 'F') IS NOT NULL) BEGIN ALTER TABLE [posts] DROP CONSTRAINT [posts_user_id_fkey];  END; ",
               "ALTER TABLE [posts] ALTER COLUMN [user_id] BIGINT; ",
               "ALTER TABLE [posts] ADD CONSTRAINT [posts_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [users]([id]) ON DELETE CASCADE; "
             ]
             |> IO.iodata_to_binary()
  end

  test "create table with options" do
    create =
      {:create, table(:posts, options: "WITH FOO=BAR"),
       [{:add, :id, :serial, [primary_key: true]}, {:add, :created_at, :datetime, []}]}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE TABLE [posts] ([id] int IDENTITY(1,1), [created_at] datetime, CONSTRAINT [PK__posts] PRIMARY KEY CLUSTERED ([id])) WITH FOO=BAR|
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'posts', 'new_posts'|
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'foo.posts', 'foo.new_posts'|
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}

    assert SQL.execute_ddl(rename) ==
             ~s|EXEC sp_rename 'posts.given_name', 'first_name', 'COLUMN'|
  end

  test "rename column in table with prefixes" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}

    assert SQL.execute_ddl(rename) ==
             ~s|EXEC sp_rename 'foo.posts.given_name', 'first_name', 'COLUMN'|
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE INDEX [posts_category_id_permalink_index] ON [posts] ([category_id], [permalink]);|

    # below should be handled with collation on column which is indexed

    # create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    # assert SQL.execute_ddl(create) ==
    #        ~s|CREATE INDEX [posts$main] ON [posts] ([lower(permalink)])|

    create =
      {:create,
       index(:posts, ["[category_id] ASC", "[permalink] DESC"], name: "IX_posts_by_category")}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE INDEX [IX_posts_by_category] ON [posts] ([category_id] ASC, [permalink] DESC);|
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE INDEX [posts_category_id_permalink_index] ON [foo].[posts] ([category_id], [permalink]);|
  end

  test "create index with prefix if not exists" do
    create = {:create_if_not_exists, index(:posts, [:category_id, :permalink], prefix: :foo)}

    assert SQL.execute_ddl(create) ==
             [
               "IF NOT EXISTS (SELECT name FROM sys.indexes ",
               "WHERE name = N'posts_category_id_permalink_index' ",
               "AND object_id = OBJECT_ID(N'foo.posts')) ",
               "CREATE INDEX [posts_category_id_permalink_index] ON [foo].[posts] ([category_id], [permalink]);"
             ]
             |> IO.iodata_to_binary()
  end

  test "create index asserting concurrency" do
    create = {:create, index(:posts, [:permalink], name: "posts$main", concurrently: true)}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE INDEX [posts$main] ON [posts] ([permalink]) LOCK=NONE;|
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE UNIQUE INDEX [posts_permalink_index] ON [posts] ([permalink]);|

    create = {:create, index(:posts, [:permalink], unique: true, prefix: :foo)}

    assert SQL.execute_ddl(create) ==
             ~s|CREATE UNIQUE INDEX [posts_permalink_index] ON [foo].[posts] ([permalink]);|
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}

    assert_raise ArgumentError, ~r"TDS adapter does not support using in indexes.", fn ->
      SQL.execute_ddl(create)
    end
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX [posts$main] ON [posts];|
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo)}

    assert SQL.execute_ddl(drop) ==
             ~s|DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts];|
  end

  test "drop index with prefix if exists" do
    drop =
      {:drop_if_exists,
       index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo)}

    assert SQL.execute_ddl(drop) ==
             [
               "IF EXISTS (SELECT name FROM sys.indexes ",
               "WHERE name = N'posts_category_id_permalink_index' ",
               "AND object_id = OBJECT_ID(N'foo.posts')) ",
               "DROP INDEX [posts_category_id_permalink_index] ON [foo].[posts];"
             ]
             |> IO.iodata_to_binary()
  end

  test "drop index asserting concurrency" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX [posts$main] ON [posts] LOCK=NONE;|
  end
end
