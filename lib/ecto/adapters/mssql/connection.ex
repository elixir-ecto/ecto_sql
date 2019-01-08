if Code.ensure_loaded?(Tds) do
  defmodule Ecto.Adapters.MsSql.Connection do
    @moduledoc false
    require Logger
    alias Tds.Query
    alias Ecto.Query.Tagged
    require Ecto.Schema
    @default_port System.get_env("MSSQLPORT") || 1433

    @behaviour Ecto.Adapters.SQL.Connection
    # @behaviour Ecto.Adapters.SQL.Query

    @unsafe_query_strings ["'\\"]

    @doc """
    Receives options and returns `DBConnection` supervisor child specification.
    """
    @spec connect(opts :: Keyword.t()) :: {module, Keyword.t()}
    def connect(opts) do
      opts
      |> Keyword.put_new(:port, @default_port)
      |> Tds.Protocol.connect()
    end

    @doc false
    def child_spec(opts) do
      opts
      |> Tds.child_spec()
    end

    # alias Tds.Parameter

    def prepare_execute(pid, _name, statement, params, opts \\ []) do
      query = %Query{statement: statement}

      {params, _} =
        Enum.map_reduce(params, 1, fn param, acc ->
          {value, type} = prepare_param(param)
          {%Tds.Parameter{name: "@#{acc}", value: value, type: type}, acc + 1}
        end)

      opts = Keyword.put(opts, :parameters, params)
      DBConnection.prepare_execute(pid, query, params, opts)
    end

    def execute(pid, statement, params, opts) when is_binary(statement) or is_list(statement) do
      query = %Query{statement: statement}

      {params, _} =
        Enum.map_reduce(params, 1, fn param, acc ->
          {value, type} = prepare_param(param)
          {%Tds.Parameter{name: "@#{acc}", value: value, type: type}, acc + 1}
        end)

      opts = Keyword.put(opts, :parameters, params)

      case DBConnection.prepare_execute(pid, query, params, opts) do
        {:ok, _, %Tds.Result{columns: nil, num_rows: num_rows, rows: []}} when num_rows > -1 ->
          {:ok, %Tds.Result{columns: nil, num_rows: num_rows, rows: nil}}

        {:ok, _, query} ->
          {:ok, query}

        {:error, _} = err ->
          err
      end
    end

    def execute(pid, %{} = query, params, opts) do
      opts = Keyword.put_new(opts, :parameters, params)

      {params, _} =
        Enum.map_reduce(params, 1, fn param, acc ->
          {value, type} = prepare_param(param)
          {%Tds.Parameter{name: "@#{acc}", value: value, type: type}, acc + 1}
        end)

      opts = Keyword.put(opts, :parameters, params)

      case DBConnection.prepare_execute(pid, query, params, opts) do
        {:ok, _, query} -> {:ok, query}
        {:error, _} = err -> err
      end
    end

    def stream(_conn, _sql, _params, _opts) do
      {:error, :not_implemented}
    end

    def query(conn, sql, params, opts) do
      {params, _} =
        Enum.map_reduce(params, 1, fn param, acc ->
          {value, type} = prepare_param(param)
          {%Tds.Parameter{name: "@#{acc}", value: value, type: type}, acc + 1}
        end)

      case Tds.query(conn, sql, params, opts) do
        {:ok, %Tds.Result{} = result} ->
          {:ok, Map.from_struct(result)}

        {:error, %Tds.Error{}} = err ->
          err
      end
    end

    def to_constraints(%Tds.Error{mssql: %{number: code, msg_text: message}}) do
      Tds.Error.get_constraint_violations(code, message)
    end

    def ddl_logs(_), do: []

    # Boolean
    defp prepare_param(%Tagged{value: true, type: :boolean}), do: {1, :boolean}
    defp prepare_param(%Tagged{value: false, type: :boolean}), do: {0, :boolean}
    # Tds.Ecto.VarChar
    defp prepare_param(%Tagged{value: value, type: :varchar}) do
      {value, :varchar}
    end

    # String parameter
    defp prepare_param(%Tagged{value: value, type: :string}), do: {value, :string}
    # DateTime
    defp prepare_param(%Tagged{
           value: {{y, m, d}, {hh, mm, ss, us}},
           type: :datetime
         })
         when us > 0,
         do: {{{y, m, d}, {hh, mm, ss, us}}, :datetime2}

    defp prepare_param(%Tagged{
           value: {{y, m, d}, {hh, mm, ss, _}},
           type: :datetime
         }) do
      {{{y, m, d}, {hh, mm, ss}}, :datetime}
    end

    # UUID and BinaryID
    defp prepare_param(%Tagged{value: value, type: type}) when type in [:binary_id, :uuid] do
      case value do
        <<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> ->
          {:ok, value} = Tds.Types.UUID.dump(value)
          {value, :uuid}

        any ->
          {any, :uuid}
      end
    end

    defp prepare_param(%Tagged{value: _, tag: Tds.Types.VarChar} = p),
      do: prepare_param(%{p | type: :varchar})

    defp prepare_param(%Tagged{value: _, tag: Tds.Types.UUID} = p),
      do: prepare_param(%{p | type: :uuid})

    # any binary
    defp prepare_param(%Tagged{value: value, type: nil}) when is_binary(value) do
      type = if String.valid?(value), do: :string, else: :binary
      {value, type}
    end

    # Binary
    defp prepare_param(%Tagged{value: value, type: :binary}), do: {value, :binary}
    # Decimal
    defp prepare_param(%Decimal{} = value) do
      {value, :decimal}
    end

    defp prepare_param(%NaiveDateTime{}=value) do
      {value, :datetime}
    end

    defp prepare_param(%DateTime{}=value) do
      {value, :datetime2}
    end

    defp prepare_param(%Date{}=value) do
      {value, :date}
    end

    defp prepare_param(%Time{}=value) do
      {value, :time}
    end

    defp prepare_param(%{__struct__: module} = _value) do
      # just in case dumpers/loaders are not defined for the this struct
      raise Tds.Error,
            "Tds is unable to convert struct `#{inspect(module)}` into supported MsSql types"
    end

    defp prepare_param(%{} = value), do: {json_library().encode!(value), :string}
    defp prepare_param(value), do: prepare_raw_param(value)

    defp prepare_raw_param(value) when is_binary(value) do
      type = if String.printable?(value), do: :string, else: :binary
      {value, type}
    end

    defp prepare_raw_param({y, m, d} = value)
         when is_integer(y) and is_integer(m) and is_integer(d),
         do: {value, :date}

    defp prepare_raw_param(value) when value == true, do: {1, :boolean}
    defp prepare_raw_param(value) when value == false, do: {0, :boolean}
    defp prepare_raw_param(value) when is_integer(value), do: {value, :integer}
    defp prepare_raw_param(value) when is_number(value), do: {value, :float}
    defp prepare_raw_param(%Decimal{} = value), do: {Decimal.new(value), :decimal}
    defp prepare_raw_param({_, :varchar} = value), do: value
    defp prepare_raw_param(value), do: {value, nil}

    defp json_library() do
      Application.get_env(:tds, :json_library)
    end

    ## Query

    alias Ecto.Query
    alias Ecto.Query.{SelectExpr, QueryExpr, JoinExpr, BooleanExpr}

    def all(query) do
      sources = create_names(query)

      from = from(query, sources)
      select = select(query, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      order_by = order_by(query, sources)

      offset = offset(query, sources)

      if query.offset != nil and query.order_bys == [],
        do: error!(query, "ORDER BY is mandatory to use OFFSET")

      assemble([select, from, join, where, group_by, having, order_by, offset])
    end

    def update_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      update = "UPDATE #{name}"
      fields = update_fields(query, sources)
      from = "FROM #{table} AS #{name}"
      join = join(query, sources)
      where = where(query, sources)

      assemble([update, "SET", fields, from, join, where])
    end

    def delete_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      delete = "DELETE #{name}"
      from = "FROM #{table} AS #{name}"
      join = join(query, sources)
      where = where(query, sources)

      assemble([delete, from, join, where])
    end

    def insert(prefix, table, header, rows, on_conflict, returning) do
      [] = on_conflict(on_conflict, header)

      values =
        if header == [] do
          returning(returning, "INSERTED") <> "DEFAULT VALUES"
        else
          "(" <>
            Enum.map_join(header, ", ", &quote_name/1) <>
            ")" <> " " <> returning(returning, "INSERTED") <> "VALUES " <> insert_all(rows, 1, "")
        end

      "INSERT INTO #{quote_table(prefix, table)} " <> values
    end

    defp on_conflict({_, _, [_ | _]}, _header) do
      error!(nil, "The :conflict_target option is not supported in insert/insert_all by TDS")
    end

    defp on_conflict({:raise, _, []}, _header) do
      []
    end

    defp on_conflict({:nothing, _, []}, [_field | _]) do
      error!(nil, "The :nothing option is not supported in insert/insert_all by TDS")
    end

    defp on_conflict({:replace_all, _, []}, _header) do
      error!(nil, "The :replace_all option is not supported in insert/insert_all by TDS")
    end

    defp on_conflict({_query, _, []}, _header) do
      error!(
        nil,
        "The query as option for on_conflict is not supported in insert/insert_all by TDS yet."
      )
    end

    defp insert_all([row | rows], counter, acc) do
      {counter, row} = insert_each(row, counter, "")
      insert_all(rows, counter, acc <> ",(" <> row <> ")")
    end

    defp insert_all([], _counter, "," <> acc) do
      acc
    end

    defp insert_each([nil | t], counter, acc), do: insert_each(t, counter, acc <> ",DEFAULT")

    defp insert_each([_ | t], counter, acc),
      do: insert_each(t, counter + 1, acc <> ", @" <> Integer.to_string(counter))

    defp insert_each([], counter, ", " <> acc), do: {counter, acc}
    defp insert_each([], counter, "," <> acc), do: {counter, acc}

    def update(prefix, table, fields, filters, returning) do
      {fields, count} =
        Enum.map_reduce(fields, 1, fn field, acc ->
          {"#{quote_name(field)} = @#{acc}", acc + 1}
        end)

      {filters, _count} =
        Enum.map_reduce(filters, count, fn
          {field, nil}, acc ->
            {"#{quote_name(field)} IS NULL", acc + 1}

          {field, _value}, acc ->
            {"#{quote_name(field)} = @#{acc}", acc + 1}

          field, acc ->
            {"#{quote_name(field)} = @#{acc}", acc + 1}
        end)

      "UPDATE #{quote_table(prefix, table)} SET " <>
        Enum.join(fields, ", ") <>
        " " <> returning(returning, "INSERTED") <> "WHERE " <> Enum.join(filters, " AND ")
    end

    def delete(prefix, table, filters, returning) do
      {filters, _} =
        Enum.map_reduce(filters, 1, fn
          {field, nil}, acc ->
            {"#{quote_name(field)} IS NULL", acc + 1}

          {field, _value}, acc ->
            {"#{quote_name(field)} = @#{acc}", acc + 1}

          field, acc ->
            {"#{quote_name(field)} = @#{acc}", acc + 1}
        end)

      "DELETE FROM #{quote_table(prefix, table)}" <>
        " " <> returning(returning, "DELETED") <> "WHERE " <> Enum.join(filters, " AND ")
    end

    ## Query generation

    binary_ops = [
      ==: "=", !=: "<>", <=: "<=", >=: ">=", <: "<", >: ">",
      +: "+", -: "-", *: "*", /: "/",
      and: "AND", or: "OR", ilike: "LIKE", like: "LIKE"
    ]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(
           %Query{
             select: %{
               fields: fields
             }
           } = query,
           sources
         ) do
      [
        "SELECT",
        distinct(query, sources),
        limit(query, sources),
        ?\s | select_fields(fields, sources, query)
      ]
      |> IO.iodata_to_binary()
    end

    defp select_fields(
           [],
           sources,
           %Query{
             select: %SelectExpr{
               expr: val
             }
           } = query
         ) do
      expr(val, sources, query)
    end

    defp select_fields(fields, sources, query) do
      [
        Enum.map_join(fields, ", ", fn
          {key, value} ->
            expr(value, sources, query) <> " AS " <> quote_name(key)

          value ->
            expr(value, sources, query)
        end)
      ]
    end

    defp distinct(%Query{distinct: nil}, _sources), do: ""
    defp distinct(%Query{distinct: []}, _sources), do: ""

    defp distinct(
           %Query{
             distinct: %QueryExpr{
               expr: true
             }
           },
           _sources
         ),
         do: " DISTINCT"

    defp distinct(
           %Query{
             distinct: %QueryExpr{
               expr: false
             }
           },
           _sources
         ),
         do: ""

    defp distinct(
           %Query{
             distinct: %QueryExpr{
               expr: _exprs
             }
           } = query,
           _sources
         ) do
      error!(query, "MSSQL does not allow expressions in distinct")
    end

    defp from(%{from: from} = query, sources) do
      {from, name} = get_source(query, sources, 0, from)

      ("FROM #{from} AS #{name}" <> lock(query.lock))
      |> String.trim()
    end

    defp update_fields(%Query{updates: updates} = query, sources) do
      for(
        %{expr: expr} <- updates,
        {op, kw} <- expr,
        {key, value} <- kw,
        do: update_op(op, key, value, sources, query)
      )
      |> Enum.join(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      {_table, name, _model} = elem(sources, 0)
      name <> "." <> quote_name(key) <> " = " <> expr(value, sources, query)
    end

    defp update_op(:inc, key, value, sources, query) do
      {_table, name, _model} = elem(sources, 0)
      quoted = quote_name(key)

      name <>
        "." <> quoted <> " = " <> name <> "." <> quoted <> " + " <> expr(value, sources, query)
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect(command)} for TDS")
    end

    defp join(%Query{joins: []}, _sources), do: nil

    defp join(%Query{joins: joins, lock: lock} = query, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{
          on: %QueryExpr{expr: _},
          qual: :cross,
          ix: ix,
          source: source
        } ->
          {join, name, _model} = elem(sources, ix)
          # qual = join_qual(qual)
          join = join || "(" <> expr(source, sources, query) <> ")"

          "CROSS JOIN #{join} AS #{name} #{lock(lock)}"

        %JoinExpr{
          on: %QueryExpr{expr: expr},
          qual: qual,
          ix: ix,
          source: source
        } ->
          {join, name, _model} = elem(sources, ix)
          qual = join_qual(qual)
          join = join || "(" <> expr(source, sources, query) <> ")"

          "#{qual} JOIN " <>
            join <> " AS #{name} " <> lock(lock) <> "ON " <> expr(expr, sources, query)
      end)
    end

    defp join_qual(:inner), do: "INNER"
    defp join_qual(:left), do: "LEFT OUTER"
    defp join_qual(:right), do: "RIGHT OUTER"
    defp join_qual(:full), do: "FULL OUTER"

    defp where(%Query{wheres: wheres} = query, sources) do
      boolean("WHERE", wheres, sources, query)
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean("HAVING", havings, sources, query)
    end

    defp group_by(%Query{group_bys: group_bys} = query, sources) do
      exprs =
        Enum.map_join(group_bys, ", ", fn %QueryExpr{expr: expr} ->
          Enum.map_join(expr, ", ", &expr(&1, sources, query))
        end)

      case exprs do
        "" -> nil
        _ -> "GROUP BY " <> exprs
      end
    end

    defp order_by(%Query{order_bys: order_bys} = query, sources) do
      exprs =
        Enum.map_join(order_bys, ", ", fn %QueryExpr{expr: expr} ->
          Enum.map_join(expr, ", ", &order_by_expr(&1, sources, query))
        end)

      case exprs do
        "" -> nil
        _ -> "ORDER BY " <> exprs
      end
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)

      case dir do
        :asc -> str
        :desc -> str <> " DESC"
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: ""

    defp limit(
           %Query{
             limit: %QueryExpr{
               expr: expr
             }
           } = query,
           sources
         ) do
      case Map.get(query, :offset) do
        nil ->
          [" TOP(", expr(expr, sources, query), ")"]
          |> IO.iodata_to_binary()

        _ ->
          ""
      end
    end

    defp offset(%Query{offset: nil}, _sources), do: nil

    defp offset(
           %Query{
             offset: %QueryExpr{
               expr: offset_expr
             },
             limit: %QueryExpr{
               expr: limit_expr
             }
           } = query,
           sources
         ) do
      [
        "OFFSET ",
        expr(offset_expr, sources, query),
        " ROW ",
        "FETCH NEXT ",
        expr(limit_expr, sources, query),
        " ROWS ONLY"
      ]
      |> IO.iodata_to_binary()
    end

    defp offset(%Query{offset: _} = query, _sources) do
      error!(query, "You must provide a limit while using an offset")
    end

    defp lock(nil), do: ""
    defp lock(lock_clause), do: " #{lock_clause} "

    defp boolean(_name, [], _sources, _query), do: []

    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      boolean_expression =
        Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
          %BooleanExpr{expr: expr, op: op}, {op, acc} ->
            {op, acc <> operator_to_boolean(op) <> paren_expr(expr, sources, query)}

          %BooleanExpr{expr: expr, op: op}, {_, acc} ->
            {op, "(" <> acc <> ")" <> operator_to_boolean(op) <> paren_expr(expr, sources, query)}
        end)
        |> elem(1)

      name <> " " <> boolean_expression
    end

    # defp boolean(name, query_exprs, sources, query) do
    #   name <> " " <>
    #     Enum.map_join(query_exprs, " AND ", fn
    #       %QueryExpr{expr: true, op: op} ->
    #         {op, "(1 = 1)"}
    #       %QueryExpr{expr: false, op: op} ->
    #         {op, "(0 = 1)"}
    #       %QueryExpr{expr: expr, op: op} ->
    #         {op, paren_expr(expr, sources, query)}
    #     end)
    # end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
      |> IO.iodata_to_binary()
    end

    # :^ - represents parameter ix is index number
    defp expr({:^, [], [idx]}, _sources, _query) do
      "@#{idx + 1}"
    end

    # :. - attribure, table alias name can be get from sources by passing index
    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
         when is_atom(field) or is_binary(field) do
      {_, name, _} = elem(sources, idx)
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {table, _name, _schema} = elem(sources, idx)

      error!(
        query,
        "MSSQL adapter does not support selecting all fields from #{table} without a schema. " <>
          "Please specify a schema or specify exactly which fields you want in projection"
      )
    end

    defp expr({:&, _, [idx, fields, _counter]}, sources, query) do
      {_table, name, schema} = elem(sources, idx)

      if is_nil(schema) and is_nil(fields) do
        error!(
          query,
          "MSSQL adapter requires a schema module when using selector #{inspect(name)} but " <>
            "none was given. Please specify schema " <>
            "or specify exactly which fields from #{inspect(name)} you what in projection"
        )
      end

      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    #         {:in, [], [1,   {:^, [], [0, 0]}]}

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "0=1"
    end

    # example from(p in Post, where: p.id in [1,2, ^some_id])
    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = Enum.map_join(right, ",", &expr(&1, sources, query))
      expr(left, sources, query) <> " IN (" <> args <> ")"
    end

    # example from(p in Post, where: p.id in [])
    defp expr({:in, _, [_left, {:^, [], [0, 0]}]}, _sources, _query), do: "0=1"
    # example from(p in Post, where: p.id in ^some_list)
    # or from(p in Post, where: p.id in ^[])
    defp expr({:in, _, [left, {:^, _, [idx, length]}]}, sources, query) do
      args = list_param_to_args(idx, length)
      expr(left, sources, query) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      expr(left, sources, query) <> " IN (" <> expr(right, sources, query) <> ")"
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      "#{expr(arg, sources, query)} IS NULL"
    end

    defp expr({:not, _, [expr]}, sources, query) do
      "NOT (" <> expr(expr, sources, query) <> ")"
    end

    defp expr({:filter, _, _}, _sources, query) do
      error!(query, "MSSQL adapter does not support aggregate filters")
    end

    defp expr(%Ecto.SubQuery{query: query}, _sources, _query) do
      all(query)
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "MSSQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map_join(parts, "", fn
        {:raw, part} -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      "CAST(DATEADD(" <>
        interval <>
        ", " <>
        interval_count(count, sources, query) <>
        ", " <> expr(datetime, sources, query) <> ") AS datetime2)"
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      "CAST(DATEADD(" <>
        interval <>
        ", " <>
        interval_count(count, sources, query) <>
        ", CAST(" <>
        expr(
          date,
          sources,
          query
        ) <> " AS datetime2)" <> ") AS date)"
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {"", args}
        end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          op_to_binary(left, sources, query) <> " #{op} " <> op_to_binary(right, sources, query)

        {:fun, fun} ->
          "#{fun}(" <> modifier <> Enum.map_join(args, ", ", &expr(&1, sources, query)) <> ")"
      end
    end

    defp expr(list, sources, query) when is_list(list) do
      Enum.map_join(list, ", ", &expr(&1, sources, query))
    end

    defp expr({string, :varchar}, _sources, _query)
         when is_binary(string) do
      "'#{escape_string(string)}'"
    end

    defp expr(string, _sources, _query) when is_binary(string) do
      if String.contains?(string, @unsafe_query_strings) do
        len = String.length(string)

        hex =
          string
          |> :unicode.characters_to_binary(:utf8, {:utf16, :little})
          |> Base.encode16(case: :lower)

        "CONVERT(nvarchar(#{len}), 0x#{hex})"
      else
        "N'#{escape_string(string)}'"
      end
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Tagged{value: binary, type: :binary}, _sources, _query) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "0x#{hex}"
    end

    defp expr(%Tagged{value: binary, type: :uuid}, _sources, _query) when is_binary(binary) do
      case binary do
        <<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> ->
          {:ok, value} = Tds.Types.UUID.dump(binary)
          value

        any ->
          any
      end
    end

    defp expr(%Tagged{value: other, type: type}, sources, query)
         when type in [:varchar, :nvarchar] do
      "CAST(#{expr(other, sources, query)} AS #{column_type(type, [])}(max))"
    end

    defp expr(%Tagged{value: other, type: type}, sources, query) do
      "CAST(#{expr(other, sources, query)} AS #{column_type(type, [])})"
    end

    defp expr(nil, _sources, _query), do: "NULL"
    defp expr(true, _sources, _query), do: "1"
    defp expr(false, _sources, _query), do: "0"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      "'#{escape_string(literal)}'"
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      String.Chars.Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      String.Chars.Float.to_string(literal)
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
      "(" <> expr(expr, sources, query) <> ")"
    end

    defp op_to_binary(expr, sources, query) do
      expr(expr, sources, query)
    end

    defp interval_count(count, _sources, _query) when is_integer(count) do
      String.Chars.Integer.to_string(count)
    end

    defp interval_count(count, _sources, _query) when is_float(count) do
      :erlang.float_to_binary(count, [:compact, decimals: 16])
    end

    defp interval_count(count, sources, query) do
      expr(count, sources, query)
    end

    defp returning([], _verb), do: ""

    defp returning(returning, verb) do
      "OUTPUT " <>
        Enum.map_join(returning, ", ", fn arg -> "#{verb}.#{quote_name(arg)}" end) <> " "
    end

    defp create_names(%{sources: sources}) do
      sources
      |> create_names(0, tuple_size(sources))
      |> List.to_tuple()
    end

    defp create_names(sources, pos, limit) when pos < limit do
      [create_name(sources, pos) | create_names(sources, pos + 1, limit)]
    end

    defp create_names(_sources, pos, pos) do
      []
    end

    defp create_name(sources, pos) do

        case elem(sources, pos) do
          {:fragment, _, _} ->
            {nil, "f" <> Integer.to_string(pos), nil}

          {table, model, prefix} ->
            name = String.first(table) <> Integer.to_string(pos)
            {quote_table(prefix, table), name, model}

          %Ecto.SubQuery{} ->
            {nil, "s" <> Integer.to_string(pos), nil}
        end
    end

    # DDL
    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    def execute_ddl({command, %Table{} = table, columns})
        when command in [:create, :create_if_not_exists] do
      prefix = table.prefix

      table_structure =
        case column_definitions(table, columns) ++
               pk_definitions(
                 columns,
                 ", CONSTRAINT [PK_#{prefix}_#{table.name}] "
               ) do
          [] -> []
          list -> [" (#{list})"]
        end

      query = [
        [
          if_table_not_exists(command == :create_if_not_exists, table.name, prefix),
          "CREATE TABLE ",
          quote_table(prefix, table.name),
          table_structure,
          engine_expr(table.engine),
          options_expr(table.options),
          if_do(command == :create_if_not_exists, "END ")
        ]
      ]

      Enum.map_join(query, "", &"#{&1}")
    end

    def execute_ddl({command, %Table{} = table}) when command in [:drop, :drop_if_exists] do
      prefix = table.prefix

      query = [
        [
          if_table_exists(command == :drop_if_exists, table.name, prefix),
          "DROP TABLE ",
          quote_table(prefix, table.name),
          if_do(command == :drop_if_exists, "END ")
        ]
      ]

      Enum.map_join(query, "", &"#{&1}")
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      statement_prefix = ["ALTER TABLE ", quote_table(table.prefix, table.name), " "]

      # todo: There is amny issues which could arase is we want to remove primary key, this needs special attention!!!
      # below is just case when we are adding pkeys, but may things are not covered:
      # 1. What if primary key was already defined?
      # 2. What if we need to drop composite key?
      # 3. What is field is removed which is in PK but developer do not specify in options?
      # 4. If developer whant to alter PK field, it could be an issue. The only way is to query database and check what is currently there!!
      pkeys =
        case pk_definitions(changes, " CONSTRAINT [PK_#{table.prefix}_#{table.name}] ") do
          [] -> []
          sql -> [statement_prefix, "ADD", sql]
        end

      [
        column_changes(statement_prefix, table, changes),
        pkeys
      ]
      |> IO.iodata_to_binary()
    end

    def execute_ddl({command, %Index{} = index})
        when command in [:create, :create_if_not_exists] do
      prefix = index.prefix

      if index.using do
        error!(nil, "MSSQL adapter does not support using in indexes.")
      end

      [
        [
          if_index_not_exists(
            command == :create_if_not_exists,
            index.name,
            unquoted_name(prefix, index.table)
          ),
          "CREATE",
          if_do(index.unique, " UNIQUE"),
          " INDEX ",
          quote_name(index.name),
          " ON ",
          quote_table(prefix, index.table),
          " ",
          "(#{intersperse_map(index.columns, ", ", &index_expr/1)})",
          # if_do(is_list(index.include), [" INCLUDE (", intersperse_map(index.columns, ", ", &index_expr/1), ")"]),
          if_do(index.using, [" USING ", to_string(index.using)]),
          if_do(index.concurrently, " LOCK=NONE"),
          ";"
        ]
      ]
      |> IO.iodata_to_binary()
    end

    def execute_ddl({:create, %Constraint{check: check}}) when is_binary(check),
      do: error!(nil, "MSSQL adapter does not support check constraints")

    def execute_ddl({:create, %Constraint{exclude: exclude}}) when is_binary(exclude),
      do: error!(nil, "MSSQL adapter does not support exclusion constraints")

    def execute_ddl({command, %Index{} = index}) when command in [:drop, :drop_if_exists] do
      prefix = index.prefix

      [
        if_index_exists(
          command == :drop_if_exists,
          index.name,
          unquoted_name(prefix, index.table)
        ),
        "DROP INDEX ",
        quote_name(index.name),
        " ON ",
        quote_table(prefix, index.table),
        if_do(index.concurrently, " LOCK=NONE"),
        ";"
      ]
      |> IO.iodata_to_binary()
    end

    def execute_ddl({:drop, %Constraint{}}),
      do: error!(nil, "MSSQL adapter does not support constraints")

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [
        [
          "EXEC sp_rename '",
          unquoted_name(current_table.prefix, current_table.name),
          "', '",
          unquoted_name(new_table.prefix, new_table.name),
          "'"
        ]
      ]
      |> IO.iodata_to_binary()
    end

    def execute_ddl({:rename, table, current_column, new_column}) do
      [
        [
          "EXEC sp_rename '",
          unquoted_name(table.prefix, table.name, current_column),
          "', '",
          unquoted_name(new_column),
          "', 'COLUMN'"
        ]
      ]
      |> IO.iodata_to_binary()
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "MSSQL adapter does not support keyword lists in execute")

    defp pk_definitions(columns, prefix) do
      pks = for {_, name, _, opts} <- columns, opts[:primary_key], do: name

      case pks do
        [] ->
          []

        _ ->
          [
            [prefix, "PRIMARY KEY CLUSTERED (#{intersperse_map(pks, ", ", &quote_name/1)})"]
            |> IO.iodata_to_binary()
          ]
      end
    end

    defp column_definitions(table, columns) do
      intersperse_map(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [
        quote_name(name),
        " ",
        reference_column_type(ref.type, opts),
        column_options(table, name, opts),
        reference_expr(ref, table, name)
      ]
    end

    defp column_definition(table, {:add, name, type, opts}) do
      [quote_name(name), " ", column_type(type, opts), column_options(table, name, opts)]
    end

    defp column_changes(statement, table, columns) do
      # intersperse_map(columns, " ", &column_change(statement, table, &1))
      for column <- columns do
        column_change(statement, table, column)
      end
    end

    defp column_change(statement_prefix, table, {:add, name, %Reference{} = ref, opts}) do
      [
        [
          statement_prefix,
          "ADD ",
          quote_name(name),
          " ",
          reference_column_type(ref.type, opts),
          column_options(table, name, opts),
          "; "
        ],
        [statement_prefix, "ADD", constraint_expr(ref, table, name), "; "]
      ]
    end

    defp column_change(statement_prefix, table, {:add, name, type, opts}) do
      [
        [
          statement_prefix,
          "ADD ",
          quote_name(name),
          " ",
          column_type(type, opts),
          column_options(table, name, opts),
          "; "
        ]
      ]
    end

    defp column_change(statement_prefix, table, {:modify, name, %Reference{} = ref, opts}) do
      fk_name = reference_name(ref, table, name)

      [
        [
          if_object_exists(
            fk_name,
            "F",
            "#{statement_prefix}DROP CONSTRAINT #{fk_name}; "
          )
        ],
        [
          statement_prefix,
          "ALTER COLUMN ",
          quote_name(name),
          " ",
          reference_column_type(ref.type, opts),
          column_options(table, name, opts),
          "; "
        ],
        [statement_prefix, "ADD", constraint_expr(ref, table, name), "; "]
      ]
    end

    defp column_change(statement_prefix, table, {:modify, name, type, opts}) do
      fk_name = constraint_name("DF", table, name)
      # has_default = Keyword.has_key?(opts, :default)
      [
        [
          if_object_exists(
            fk_name,
            "D",
            "#{statement_prefix}DROP CONSTRAINT #{fk_name}; "
          )
        ],
        [
          statement_prefix,
          "ALTER COLUMN ",
          quote_name(name),
          " ",
          column_type(type, opts),
          null_expr(Keyword.get(opts, :null)),
          "; "
        ],
        [column_default_value(statement_prefix, table, name, opts)]
      ]
    end

    defp column_change(statement_prefix, _table, {:remove, name}) do
      [statement_prefix, "DROP COLUMN ", quote_name(name), "; "]
    end

    defp column_options(table, name, opts) do
      default = Keyword.fetch(opts, :default)
      null = Keyword.get(opts, :null)
      [null_expr(null), default_expr(table, name, default)]
    end

    defp column_default_value(statement_prefix, table, name, opts) do
      default_expression = default_expr(table, name, Keyword.fetch(opts, :default))

      case default_expression do
        [] -> []
        _ -> [statement_prefix, "ADD", default_expression, " FOR ", quote_name(name), "; "]
      end
    end

    defp null_expr(false), do: [" NOT NULL"]
    defp null_expr(true), do: [" NULL"]
    defp null_expr(_), do: []

    defp default_expr(table, name, {:ok, nil}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (NULL)"]

    defp default_expr(table, name, {:ok, literal}) when is_binary(literal),
      do: [
        " CONSTRAINT ",
        constraint_name("DF", table, name),
        " DEFAULT (N'",
        escape_string(literal),
        "')"
      ]

    defp default_expr(table, name, {:ok, true}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (1)"]

    defp default_expr(table, name, {:ok, false}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (0)"]

    defp default_expr(table, name, {:ok, literal}) when is_number(literal),
      do: [
        " CONSTRAINT ",
        constraint_name("DF", table, name),
        " DEFAULT (",
        to_string(literal),
        ")"
      ]

    defp default_expr(table, name, {:ok, {:fragment, expr}}),
      do: [" CONSTRAINT ", constraint_name("DF", table, name), " DEFAULT (", expr, ")"]

    defp default_expr(_table, _name, :error), do: []

    defp constraint_name(type, table, name),
      do: quote_name("#{type}_#{table.prefix}_#{table.name}_#{name}")

    defp index_expr(literal) when is_binary(literal), do: literal
    defp index_expr(literal), do: quote_name(literal)

    defp engine_expr(_storage_engine), do: [""]

    defp options_expr(nil), do: []

    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "MSSQL adapter does not support keyword lists in :options")

    defp options_expr(options), do: [" ", to_string(options)]

    defp column_type(type, opts) do
      size = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale = Keyword.get(opts, :scale)
      ecto_to_db(type, size, precision, scale)
    end

    defp constraint_expr(%Reference{} = ref, table, name) do
      [
        " CONSTRAINT ",
        reference_name(ref, table, name),
        " FOREIGN KEY (#{quote_name(name)})",
        " REFERENCES ",
        quote_table(table.prefix, ref.table),
        "(#{quote_name(ref.column)})",
        reference_on_delete(ref.on_delete),
        reference_on_update(ref.on_update)
      ]
    end

    defp reference_expr(%Reference{} = ref, table, name) do
      [",", constraint_expr(ref, table, name)]
      |> Enum.map_join("", &"#{&1}")
    end

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")

    defp reference_name(%Reference{name: name}, _table, _column), do: quote_name(name)

    defp reference_column_type(:id, _opts), do: "BIGINT"
    defp reference_column_type(:serial, _opts), do: "INT"
    defp reference_column_type(:bigserial, _opts), do: "BIGINT"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(_), do: []

    ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      {expr || paren_expr(source, sources, query), name}
    end

    defp quote_name(name)
    defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))

    defp quote_name(name) do
      if String.contains?(name, "[") or String.contains?(name, "]") do
        error!(nil, "bad field name #{inspect(name)} '[' and ']' are not permited")
      end

      "[#{name}]"
    end

    defp quote_table(nil, name), do: quote_table(name)

    defp quote_table(prefix, name),
      do: Enum.map_join([quote_table(prefix), ".", quote_table(name)], "", &"#{&1}")

    defp quote_table(name) when is_atom(name), do: quote_table(Atom.to_string(name))

    defp quote_table(name) do
      if String.contains?(name, "[") or String.contains?(name, "]") do
        error!(nil, "bad table name #{inspect(name)} '[' and ']' are not permited")
      end

      "[#{name}]"
    end

    defp unquoted_name(prefix, name, column_name),
      do: unquoted_name(unquoted_name(prefix, name), column_name)

    defp unquoted_name(nil, name), do: unquoted_name(name)

    defp unquoted_name(prefix, name) do
      prefix = if is_atom(prefix), do: Atom.to_string(prefix), else: prefix
      name = if is_atom(name), do: Atom.to_string(name), else: name

      [prefix, ".", name]
      |> IO.iodata_to_binary()
    end

    defp unquoted_name(name) when is_atom(name), do: unquoted_name(Atom.to_string(name))

    defp unquoted_name(name) do
      if String.contains?(name, "[") or String.contains?(name, "]") do
        error!(nil, "bad table name #{inspect(name)} '[' and ']' are not permited")
      end

      name
    end

    defp intersperse_map(list, separator, mapper, acc \\ [])
    defp intersperse_map([], _separator, _mapper, acc), do: acc
    defp intersperse_map([elem], _separator, mapper, acc), do: acc ++ mapper.(elem)

    defp intersperse_map([elem | rest], separator, mapper, acc) do
      statement =
        [mapper.(elem), separator]
        |> IO.iodata_to_binary()

      acc = acc ++ [statement]
      intersperse_map(rest, separator, mapper, acc)
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      value
      |> :binary.replace("'", "''", [:global])
    end

    defp ecto_to_db(type, size, precision, scale, query \\ nil)
    defp ecto_to_db({:array, _}, _, _, _, query),
      do: error!(query, "Array type is not supported by TDS")
    defp ecto_to_db(:id, _, _, _, _),                   do: "bigint"
    defp ecto_to_db(:serial, _, _, _, _),               do: "int IDENTITY(1,1)"
    defp ecto_to_db(:bigserial, _, _, _, _),            do: "bigint IDENTITY(1,1)"
    defp ecto_to_db(:binary_id, _, _, _, _),            do: "uniqueidentifier"
    defp ecto_to_db(:boolean, _, _, _, _),              do: "bit"
    defp ecto_to_db(:string, size, _, _, _)
      when is_integer(size) and size > 0,               do: "nvarchar(#{size})"
    defp ecto_to_db(:string, :max, _, _, _),            do: "nvarchar(max)"
    defp ecto_to_db(:string, _, _, _, _),               do: "nvarchar(255)"
    defp ecto_to_db(:float, _, _, _, _),                do: "float"
    defp ecto_to_db(:binary, size, _, _, _)
      when is_integer(size) and size > 0,               do: "varbinary(#{size})"
    defp ecto_to_db(:binary, :max, _, _, _),            do: "varbinary(max)"
    defp ecto_to_db(:binary, nil, _, _, _),             do: "varbinary(2000)"
    defp ecto_to_db(:uuid, _, _, _, _),                 do: "uniqueidentifier"
    defp ecto_to_db(:map, size, _, _, _)
      when is_integer(size) and size > 0,               do: "nvarchar(#{size})"
    defp ecto_to_db(:map, :max, _, _, _),               do: "nvarchar(max)"
    defp ecto_to_db(:map, _, _, _, _),                  do: "nvarchar(2000)"
    defp ecto_to_db({:map, _}, size, _, _, _)
      when is_integer(size) and size > 0,               do: "nvarchar(#{size})"
    defp ecto_to_db({:map, _}, :max, _, _, _),          do: "nvarchar(max)"
    defp ecto_to_db({:map, _}, _, _, _, _),             do: "nvarchar(2000)"
    defp ecto_to_db(:time_usec, _, _, _, _),            do: "time"
    defp ecto_to_db(:utc_datetime, _, _, _, _),         do: "datetime"
    defp ecto_to_db(:utc_datetime_usec, _, _, _, _),    do: "datetime2"
    defp ecto_to_db(:naive_datetime, _, _, _, _),       do: "datetime"
    defp ecto_to_db(:naive_datetime_usec, _, _, _, _),  do: "datetime2"
    defp ecto_to_db(other, size, _, _, _) when is_integer(size) do
      "#{Atom.to_string(other)}(#{size})"
    end
    defp ecto_to_db(other, _, precision, scale, _) when is_integer(precision) do
      "#{Atom.to_string(other)}(#{precision},#{scale || 0})"
    end
    defp ecto_to_db(other, nil, nil, nil, _) do
      Atom.to_string(other)
    end

    defp assemble(list) do
      list
      |> List.flatten()
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(" ")
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end

    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end

    defp if_table_not_exists(condition, name, prefix) do
      if condition do
        query_segment = [
          "IF NOT EXISTS ( ",
          "SELECT * ",
          "FROM [INFORMATION_SCHEMA].[TABLES] info ",
          "WHERE info.[TABLE_NAME] = '#{name}' ",
          "AND ('#{prefix}' = '' OR info.[TABLE_SCHEMA] = '#{prefix}') ",
          ") BEGIN "
        ]

        Enum.map_join(query_segment, "", &"#{&1}")
      else
        []
      end
    end

    defp if_table_exists(condition, name, prefix) do
      if condition do
        query_segment = [
          "IF EXISTS ( ",
          "SELECT * ",
          "FROM [INFORMATION_SCHEMA].[TABLES] info ",
          "WHERE info.[TABLE_NAME] = '#{name}' ",
          "AND ('#{prefix}' = '' OR info.[TABLE_SCHEMA] = '#{prefix}') ",
          ") BEGIN "
        ]

        Enum.map_join(query_segment, "", &"#{&1}")
      else
        []
      end
    end

    defp list_param_to_args(idx, length) do
      Enum.map_join(1..length, ",", &"@#{idx + &1}")
    end

    defp as_string(atom) when is_atom(atom), do: Atom.to_string(atom)
    defp as_string(str), do: str

    defp if_index_exists(condition, index_name, table_name) do
      if condition do
        [
          "IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'",
          as_string(index_name),
          "' AND object_id = OBJECT_ID(N'",
          as_string(table_name),
          "')) "
        ]
      else
        []
      end
    end

    defp if_index_not_exists(condition, index_name, table_name) do
      if condition do
        [
          "IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'",
          as_string(index_name),
          "' AND object_id = OBJECT_ID(N'",
          as_string(table_name),
          "')) "
        ]
      else
        []
      end
    end

    # types
    # "U" - table,
    # "C", "PK", "UQ", "F ", "D " - constraints
    defp if_object_exists(name, type, statement) do
      [
        "IF (OBJECT_ID(N'", name, "', '", type, "') IS NOT NULL) BEGIN ",
        statement,
        " END; "
      ]
    end
  end
end
