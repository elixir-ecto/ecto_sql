if Code.ensure_loaded?(Postgrex) do
  defmodule Ecto.Adapters.Postgres.Connection do
    @moduledoc false

    @default_port 5432
    @behaviour Ecto.Adapters.SQL.Connection

    ## Module and Options

    @impl true
    def child_spec(opts) do
      opts
      |> Keyword.put_new(:port, @default_port)
      |> Postgrex.child_spec()
    end

    @impl true
    def to_constraints(%Postgrex.Error{postgres: %{code: :unique_violation, constraint: constraint}}, _opts),
      do: [unique: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :foreign_key_violation, constraint: constraint}}, _opts),
      do: [foreign_key: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :exclusion_violation, constraint: constraint}}, _opts),
      do: [exclusion: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :check_violation, constraint: constraint}}, _opts),
      do: [check: constraint]

    # Postgres 9.2 and earlier does not provide the constraint field
    @impl true
    def to_constraints(%Postgrex.Error{postgres: %{code: :unique_violation, message: message}}, _opts) do
      case :binary.split(message, " unique constraint ") do
        [_, quoted] -> [unique: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}}, _opts) do
      case :binary.split(message, " foreign key constraint ") do
        [_, quoted] ->
          [quoted | _] = :binary.split(quoted, " on table ")
          [foreign_key: strip_quotes(quoted)]
        _ ->
          []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :exclusion_violation, message: message}}, _opts) do
      case :binary.split(message, " exclusion constraint ") do
        [_, quoted] -> [exclusion: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :check_violation, message: message}}, _opts) do
      case :binary.split(message, " check constraint ") do
        [_, quoted] -> [check: strip_quotes(quoted)]
        _ -> []
      end
    end

    def to_constraints(_, _opts),
      do: []

    defp strip_quotes(quoted) do
      size = byte_size(quoted) - 2
      <<_, unquoted::binary-size(size), _>> = quoted
      unquoted
    end

    ## Query

    @impl true
    def prepare_execute(conn, name, sql, params, opts) do
      Postgrex.prepare_execute(conn, name, sql, params, opts)
    end

    @impl true
    def query(conn, sql, params, opts) do
      Postgrex.query(conn, sql, params, opts)
    end

    @impl true
    def execute(conn, %{ref: ref} = query, params, opts) do
      case Postgrex.execute(conn, query, params, opts) do
        {:ok, %{ref: ^ref}, result} ->
          {:ok, result}

        {:ok, _, _} = ok ->
          ok

        {:error, %Postgrex.QueryError{} = err} ->
          {:reset, err}

        {:error, %Postgrex.Error{postgres: %{code: :feature_not_supported}} = err} ->
          {:reset, err}

        {:error, _} = error ->
          error
      end
    end

    @impl true
    def stream(conn, sql, params, opts) do
      Postgrex.stream(conn, sql, params, opts)
    end

    @parent_as __MODULE__
    alias Ecto.Query.{BooleanExpr, JoinExpr, QueryExpr, WithExpr}

    @impl true
    def all(query, as_prefix \\ []) do
      sources = create_names(query, as_prefix)
      {select_distinct, order_by_distinct} = distinct(query.distinct, sources, query)

      cte = cte(query, sources)
      from = from(query, sources)
      select = select(query, select_distinct, sources)
      join = join(query, sources)
      where = where(query, sources)
      group_by = group_by(query, sources)
      having = having(query, sources)
      window = window(query, sources)
      combinations = combinations(query)
      order_by = order_by(query, order_by_distinct, sources)
      limit = limit(query, sources)
      offset = offset(query, sources)
      lock = lock(query, sources)

      [cte, select, from, join, where, group_by, having, window, combinations, order_by, limit, offset | lock]
    end

    @impl true
    def update_all(%{from: %{source: source}} = query, prefix \\ nil) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {from, name} = get_source(query, sources, 0, source)

      prefix = prefix || ["UPDATE ", from, " AS ", name | " SET "]
      fields = update_fields(query, sources)
      {join, wheres} = using_join(query, :update_all, "FROM", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [cte, prefix, fields, join, where | returning(query, sources)]
    end

    @impl true
    def delete_all(%{from: from} = query) do
      sources = create_names(query, [])
      cte = cte(query, sources)
      {from, name} = get_source(query, sources, 0, from)

      {join, wheres} = using_join(query, :delete_all, "USING", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [cte, "DELETE FROM ", from, " AS ", name, join, where | returning(query, sources)]
    end

    @impl true
    def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
      counter_offset = length(placeholders) + 1
      values =
        if header == [] do
          [" VALUES " | intersperse_map(rows, ?,, fn _ -> "(DEFAULT)" end)]
        else
          [" (", quote_names(header), ") " | insert_all(rows, counter_offset)]
        end

      ["INSERT INTO ", quote_table(prefix, table), insert_as(on_conflict),
       values, on_conflict(on_conflict, header) | returning(returning)]
    end

    defp insert_as({%{sources: sources}, _, _}) do
      {_expr, name, _schema} = create_name(sources, 0, [])
      [" AS " | name]
    end
    defp insert_as({_, _, _}) do
      []
    end

    defp on_conflict({:raise, _, []}, _header),
      do: []
    defp on_conflict({:nothing, _, targets}, _header),
      do: [" ON CONFLICT ", conflict_target(targets) | "DO NOTHING"]
    defp on_conflict({fields, _, targets}, _header) when is_list(fields),
      do: [" ON CONFLICT ", conflict_target!(targets), "DO " | replace(fields)]
    defp on_conflict({query, _, targets}, _header),
      do: [" ON CONFLICT ", conflict_target!(targets), "DO " | update_all(query, "UPDATE SET ")]

    defp conflict_target!([]),
      do: error!(nil, "the :conflict_target option is required on upserts by PostgreSQL")
    defp conflict_target!(target),
      do: conflict_target(target)

    defp conflict_target({:constraint, constraint}),
      do: ["ON CONSTRAINT ", quote_name(constraint), ?\s]
    defp conflict_target({:unsafe_fragment, fragment}),
      do: [fragment, ?\s]
    defp conflict_target([]),
      do: []
    defp conflict_target(targets),
      do: [?(, quote_names(targets), ?), ?\s]

    defp replace(fields) do
      ["UPDATE SET " |
       intersperse_map(fields, ?,, fn field ->
         quoted = quote_name(field)
         [quoted, " = ", "EXCLUDED." | quoted]
       end)]
    end

    defp insert_all(query = %Ecto.Query{}, _counter) do
      [?(, all(query), ?)]
    end

    defp insert_all(rows, counter) do
      ["VALUES ", intersperse_reduce(rows, ?,, counter, fn row, counter ->
        {row, counter} = insert_each(row, counter)
        {[?(, row, ?)], counter}
      end)
      |> elem(0)]
    end

    defp insert_each(values, counter) do
      intersperse_reduce(values, ?,, counter, fn
        nil, counter ->
          {"DEFAULT", counter}

        {%Ecto.Query{} = query, params_counter}, counter ->
          {[?(, all(query), ?)], counter + params_counter}

        {:placeholder, placeholder_index}, counter ->
          {[?$ | placeholder_index], counter}

        _, counter ->
          {[?$ | Integer.to_string(counter)], counter + 1}
      end)
    end

    @impl true
    def update(prefix, table, fields, filters, returning) do
      {fields, count} = intersperse_reduce(fields, ", ", 1, fn field, acc ->
        {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
      end)

      {filters, _count} = intersperse_reduce(filters, " AND ", count, fn
        {field, nil}, acc ->
          {[quote_name(field), " IS NULL"], acc}

        {field, _value}, acc ->
          {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
      end)

      ["UPDATE ", quote_table(prefix, table), " SET ",
       fields, " WHERE ", filters | returning(returning)]
    end

    @impl true
    def delete(prefix, table, filters, returning) do
      {filters, _} = intersperse_reduce(filters, " AND ", 1, fn
        {field, nil}, acc ->
          {[quote_name(field), " IS NULL"], acc}

        {field, _value}, acc ->
          {[quote_name(field), " = $" | Integer.to_string(acc)], acc + 1}
      end)

      ["DELETE FROM ", quote_table(prefix, table), " WHERE ", filters | returning(returning)]
    end

    @impl true
    def explain_query(conn, query, params, opts) do
      {explain_opts, opts} =
        Keyword.split(opts, ~w[analyze verbose costs settings buffers timing summary format]a)

      map_format? = {:format, :map} in explain_opts

      case query(conn, build_explain_query(query, explain_opts), params, opts) do
        {:ok, %Postgrex.Result{rows: rows}} when map_format? ->
          {:ok, List.flatten(rows)}
        {:ok, %Postgrex.Result{rows: rows}} ->
          {:ok, Enum.map_join(rows, "\n", & &1)}
        error -> error
      end
    end

    def build_explain_query(query, []) do
      ["EXPLAIN ", query]
      |> IO.iodata_to_binary()
    end

    def build_explain_query(query, opts) do
      {analyze, opts} = Keyword.pop(opts, :analyze)
      {verbose, opts} = Keyword.pop(opts, :verbose)

      # Given only ANALYZE or VERBOSE opts we assume the legacy format
      # to support all Postgres versions, otherwise assume the new
      # syntax supported since v9.0
      case opts do
        [] ->
          [
            "EXPLAIN ",
            if_do(quote_boolean(analyze) == "TRUE", "ANALYZE "),
            if_do(quote_boolean(verbose) == "TRUE", "VERBOSE "),
            query
          ]

        opts ->
          opts =
            ([analyze: analyze, verbose: verbose] ++ opts)
            |> Enum.reduce([], fn
              {_, nil}, acc ->
                acc

              {:format, value}, acc ->
                [String.upcase("#{format_to_sql(value)}") | acc]

              {opt, value}, acc ->
                [String.upcase("#{opt} #{quote_boolean(value)}") | acc]
            end)
            |> Enum.reverse()
            |> Enum.join(", ")

          ["EXPLAIN ( ", opts, " ) ", query]
      end
      |> IO.iodata_to_binary()
    end

    ## Query generation

    binary_ops =
      [==: " = ", !=: " != ", <=: " <= ", >=: " >= ", <: " < ", >: " > ",
       +: " + ", -: " - ", *: " * ", /: " / ",
       and: " AND ", or: " OR ", ilike: " ILIKE ", like: " LIKE "]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%{select: %{fields: fields}} = query, select_distinct, sources) do
      ["SELECT", select_distinct, ?\s | select_fields(fields, sources, query)]
    end

    defp select_fields([], _sources, _query),
      do: "TRUE"
    defp select_fields(fields, sources, query) do
      intersperse_map(fields, ", ", fn
        {:&, _, [idx]} ->
          case elem(sources, idx) do
            {source, _, nil} ->
              error!(query, "PostgreSQL does not support selecting all fields from #{source} without a schema. " <>
                            "Please specify a schema or specify exactly which fields you want to select")
            {_, source, _} ->
              source
          end
        {key, value} ->
          [expr(value, sources, query), " AS " | quote_name(key)]
        value ->
          expr(value, sources, query)
      end)
    end

    defp distinct(nil, _, _), do: {[], []}
    defp distinct(%QueryExpr{expr: []}, _, _), do: {[], []}
    defp distinct(%QueryExpr{expr: true}, _, _), do: {" DISTINCT", []}
    defp distinct(%QueryExpr{expr: false}, _, _), do: {[], []}
    defp distinct(%QueryExpr{expr: exprs}, sources, query) do
      {[" DISTINCT ON (",
        intersperse_map(exprs, ", ", fn {_, expr} -> expr(expr, sources, query) end), ?)],
       exprs}
    end

    defp from(%{from: %{hints: [_ | _]}} = query, _sources) do
      error!(query, "table hints are not supported by PostgreSQL")
    end

    defp from(%{from: %{source: source}} = query, sources) do
      {from, name} = get_source(query, sources, 0, source)
      [" FROM ", from, " AS " | name]
    end

    defp cte(%{with_ctes: %WithExpr{recursive: recursive, queries: [_ | _] = queries}} = query, sources) do
      recursive_opt = if recursive, do: "RECURSIVE ", else: ""
      ctes = intersperse_map(queries, ", ", &cte_expr(&1, sources, query))
      ["WITH ", recursive_opt, ctes, " "]
    end

    defp cte(%{with_ctes: _}, _), do: []

    defp cte_expr({name, cte}, sources, query) do
      [quote_name(name), " AS ", cte_query(cte, sources, query)]
    end

    defp cte_query(%Ecto.Query{} = query, sources, parent_query) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      ["(", all(query, subquery_as_prefix(sources)), ")"]
    end

    defp cte_query(%QueryExpr{expr: expr}, sources, query) do
      expr(expr, sources, query)
    end

    defp update_fields(%{updates: updates} = query, sources) do
      for(%{expr: expr} <- updates,
          {op, kw} <- expr,
          {key, value} <- kw,
          do: update_op(op, key, value, sources, query)) |> Enum.intersperse(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      [quote_name(key), " = " | expr(value, sources, query)]
    end

    defp update_op(:inc, key, value, sources, query) do
      [quote_name(key), " = ", quote_qualified_name(key, sources, 0), " + " |
       expr(value, sources, query)]
    end

    defp update_op(:push, key, value, sources, query) do
      [quote_name(key), " = array_append(", quote_qualified_name(key, sources, 0),
       ", ", expr(value, sources, query), ?)]
    end

    defp update_op(:pull, key, value, sources, query) do
      [quote_name(key), " = array_remove(", quote_qualified_name(key, sources, 0),
       ", ", expr(value, sources, query), ?)]
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "unknown update operation #{inspect command} for PostgreSQL")
    end

    defp using_join(%{joins: []}, _kind, _prefix, _sources), do: {[], []}
    defp using_join(%{joins: joins} = query, kind, prefix, sources) do
      froms =
        intersperse_map(joins, ", ", fn
          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            [join, " AS " | name]
          %JoinExpr{qual: qual} ->
            error!(query, "PostgreSQL supports only inner joins on #{kind}, got: `#{qual}`")
        end)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
            value != true,
            do: expr |> Map.put(:__struct__, BooleanExpr) |> Map.put(:op, :and)

      {[?\s, prefix, ?\s | froms], wheres}
    end

    defp join(%{joins: []}, _sources), do: []
    defp join(%{joins: joins} = query, sources) do
      [?\s | intersperse_map(joins, ?\s, fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
          if hints != [] do
            error!(query, "table hints are not supported by PostgreSQL")
          end

          {join, name} = get_source(query, sources, ix, source)
          [join_qual(qual), join, " AS ", name | join_on(qual, expr, sources, query)]
      end)]
    end

    defp join_on(:cross, true, _sources, _query), do: []
    defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

    defp join_qual(:inner), do: "INNER JOIN "
    defp join_qual(:inner_lateral), do: "INNER JOIN LATERAL "
    defp join_qual(:left),  do: "LEFT OUTER JOIN "
    defp join_qual(:left_lateral),  do: "LEFT OUTER JOIN LATERAL "
    defp join_qual(:right), do: "RIGHT OUTER JOIN "
    defp join_qual(:full),  do: "FULL OUTER JOIN "
    defp join_qual(:cross), do: "CROSS JOIN "

    defp where(%{wheres: wheres} = query, sources) do
      boolean(" WHERE ", wheres, sources, query)
    end

    defp having(%{havings: havings} = query, sources) do
      boolean(" HAVING ", havings, sources, query)
    end

    defp group_by(%{group_bys: []}, _sources), do: []
    defp group_by(%{group_bys: group_bys} = query, sources) do
      [" GROUP BY " |
       intersperse_map(group_bys, ", ", fn
         %QueryExpr{expr: expr} ->
           intersperse_map(expr, ", ", &expr(&1, sources, query))
       end)]
    end

    defp window(%{windows: []}, _sources), do: []
    defp window(%{windows: windows} = query, sources) do
      [" WINDOW " |
       intersperse_map(windows, ", ", fn {name, %{expr: kw}} ->
         [quote_name(name), " AS " | window_exprs(kw, sources, query)]
       end)]
    end

    defp window_exprs(kw, sources, query) do
      [?(, intersperse_map(kw, ?\s, &window_expr(&1, sources, query)), ?)]
    end

    defp window_expr({:partition_by, fields}, sources, query) do
      ["PARTITION BY " | intersperse_map(fields, ", ", &expr(&1, sources, query))]
    end

    defp window_expr({:order_by, fields}, sources, query) do
      ["ORDER BY " | intersperse_map(fields, ", ", &order_by_expr(&1, sources, query))]
    end

    defp window_expr({:frame, {:fragment, _, _} = fragment}, sources, query) do
      expr(fragment, sources, query)
    end

    defp order_by(%{order_bys: []}, _distinct, _sources), do: []
    defp order_by(%{order_bys: order_bys} = query, distinct, sources) do
      order_bys = Enum.flat_map(order_bys, & &1.expr)
      order_bys = order_by_concat(distinct, order_bys)
      [" ORDER BY " | intersperse_map(order_bys, ", ", &order_by_expr(&1, sources, query))]
    end

    defp order_by_concat([head | left], [head | right]), do: [head | order_by_concat(left, right)]
    defp order_by_concat(left, right), do: left ++ right

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)

      case dir do
        :asc  -> str
        :asc_nulls_last -> [str | " ASC NULLS LAST"]
        :asc_nulls_first -> [str | " ASC NULLS FIRST"]
        :desc -> [str | " DESC"]
        :desc_nulls_last -> [str | " DESC NULLS LAST"]
        :desc_nulls_first -> [str | " DESC NULLS FIRST"]
      end
    end

    defp limit(%{limit: nil}, _sources), do: []
    defp limit(%{limit: %QueryExpr{expr: expr}} = query, sources) do
      [" LIMIT " | expr(expr, sources, query)]
    end

    defp offset(%{offset: nil}, _sources), do: []
    defp offset(%{offset: %QueryExpr{expr: expr}} = query, sources) do
      [" OFFSET " | expr(expr, sources, query)]
    end

    defp combinations(%{combinations: combinations}) do
      Enum.map(combinations, fn
        {:union, query} -> [" UNION (", all(query), ")"]
        {:union_all, query} -> [" UNION ALL (", all(query), ")"]
        {:except, query} -> [" EXCEPT (", all(query), ")"]
        {:except_all, query} -> [" EXCEPT ALL (", all(query), ")"]
        {:intersect, query} -> [" INTERSECT (", all(query), ")"]
        {:intersect_all, query} -> [" INTERSECT ALL (", all(query), ")"]
      end)
    end

    defp lock(%{lock: nil}, _sources), do: []
    defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [?\s | binary]
    defp lock(%{lock: expr} = query, sources), do: [?\s | expr(expr, sources, query)]

    defp boolean(_name, [], _sources, _query), do: []
    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      [name |
       Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
         %BooleanExpr{expr: expr, op: op}, {op, acc} ->
           {op, [acc, operator_to_boolean(op), paren_expr(expr, sources, query)]}
         %BooleanExpr{expr: expr, op: op}, {_, acc} ->
           {op, [?(, acc, ?), operator_to_boolean(op), paren_expr(expr, sources, query)]}
       end) |> elem(1)]
    end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp parens_for_select([first_expr | _] = expr) do
      if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select/i) do
        [?(, expr, ?)]
      else
        expr
      end
    end

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
    end

    defp expr({:^, [], [ix]}, _sources, _query) do
      [?$ | Integer.to_string(ix + 1)]
    end

    defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
         when is_atom(field) do
      {ix, sources} = get_parent_sources_ix(query, as)
      quote_qualified_name(field, sources, ix)
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
      quote_qualified_name(field, sources, idx)
    end

    defp expr({:&, _, [idx]}, sources, _query) do
      {_, source, _} = elem(sources, idx)
      source
    end

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = intersperse_map(right, ?,, &expr(&1, sources, query))
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [left, {:^, _, [ix, _]}]}, sources, query) do
      [expr(left, sources, query), " = ANY($", Integer.to_string(ix + 1), ?)]
    end

    defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
      [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      [expr(left, sources, query), " = ANY(", expr(right, sources, query), ?)]
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      [expr(arg, sources, query) | " IS NULL"]
    end

    defp expr({:not, _, [expr]}, sources, query) do
      ["NOT (", expr(expr, sources, query), ?)]
    end

    defp expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
      query = put_in(query.aliases[@parent_as], {parent_query, sources})
      [?(, all(query, subquery_as_prefix(sources)), ?)]
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "PostgreSQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map(parts, fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
      |> parens_for_select
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      [expr(datetime, sources, query), type_unless_typed(datetime, "timestamp"), " + ",
       interval(count, interval, sources, query)]
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      [?(, expr(date, sources, query), type_unless_typed(date, "date"), " + ",
       interval(count, interval, sources, query) | ")::date"]
    end

    defp expr({:json_extract_path, _, [expr, path]}, sources, query) do
      path =
        intersperse_map(path, ?,, fn
          binary when is_binary(binary) ->
            [?", escape_json_key(binary), ?"]

          integer when is_integer(integer) ->
            Integer.to_string(integer)
        end)

      [?(, expr(expr, sources, query), "#>'{", path, "}')"]
    end

    defp expr({:filter, _, [agg, filter]}, sources, query) do
      aggregate = expr(agg, sources, query)
      [aggregate, " FILTER (WHERE ", expr(filter, sources, query), ?)]
    end

    defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER " | quote_name(name)]
    end

    defp expr({:over, _, [agg, kw]}, sources, query) do
      aggregate = expr(agg, sources, query)
      [aggregate, " OVER ", window_exprs(kw, sources, query)]
    end

    defp expr({:{}, _, elems}, sources, query) do
      [?(, intersperse_map(elems, ?,, &expr(&1, sources, query)), ?)]
    end

    defp expr({:count, _, []}, _sources, _query), do: "count(*)"

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {[], args}
        end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          [maybe_paren(left, sources, query), op | maybe_paren(right, sources, query)]
        {:fun, fun} ->
          [fun, ?(, modifier, intersperse_map(args, ", ", &expr(&1, sources, query)), ?)]
      end
    end

    defp expr(list, sources, query) when is_list(list) do
      ["ARRAY[", intersperse_map(list, ?,, &expr(&1, sources, query)), ?]]
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
        when is_binary(binary) do
      ["'\\x", Base.encode16(binary, case: :lower) | "'::bytea"]
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      [maybe_paren(other, sources, query), ?:, ?: | tagged_to_db(type)]
    end

    defp expr(nil, _sources, _query),   do: "NULL"
    defp expr(true, _sources, _query),  do: "TRUE"
    defp expr(false, _sources, _query), do: "FALSE"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      [?\', escape_string(literal), ?\']
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      [Float.to_string(literal) | "::float"]
    end

    defp type_unless_typed(%Ecto.Query.Tagged{}, _type), do: []
    defp type_unless_typed(_, type), do: [?:, ?: | type]

    # Always use the largest possible type for integers
    defp tagged_to_db(:id), do: "bigint"
    defp tagged_to_db(:integer), do: "bigint"
    defp tagged_to_db({:array, type}), do: [tagged_to_db(type), ?[, ?]]
    defp tagged_to_db(type), do: ecto_to_db(type)

    defp interval(count, interval, _sources, _query) when is_integer(count) do
      ["interval '", String.Chars.Integer.to_string(count), ?\s, interval, ?\']
    end

    defp interval(count, interval, _sources, _query) when is_float(count) do
      count = :erlang.float_to_binary(count, [:compact, decimals: 16])
      ["interval '", count, ?\s, interval, ?\']
    end

    defp interval(count, interval, sources, query) do
      [?(, expr(count, sources, query), "::numeric * ",
       interval(1, interval, sources, query), ?)]
    end

    defp maybe_paren({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
      do: paren_expr(expr, sources, query)

    defp maybe_paren({:is_nil, _, [_]} = expr, sources, query),
      do: paren_expr(expr, sources, query)

    defp maybe_paren(expr, sources, query),
      do: expr(expr, sources, query)

    defp returning(%{select: nil}, _sources),
      do: []
    defp returning(%{select: %{fields: fields}} = query, sources),
      do: [" RETURNING " | select_fields(fields, sources, query)]

    defp returning([]),
      do: []
    defp returning(returning),
      do: [" RETURNING " | quote_names(returning)]

    defp create_names(%{sources: sources}, as_prefix) do
      create_names(sources, 0, tuple_size(sources), as_prefix) |> List.to_tuple()
    end

    defp create_names(sources, pos, limit, as_prefix) when pos < limit do
      [create_name(sources, pos, as_prefix) | create_names(sources, pos + 1, limit, as_prefix)]
    end

    defp create_names(_sources, pos, pos, as_prefix) do
      [as_prefix]
    end

    defp subquery_as_prefix(sources) do
      [?s | :erlang.element(tuple_size(sources), sources)]
    end

    defp create_name(sources, pos, as_prefix) do
      case elem(sources, pos) do
        {:fragment, _, _} ->
          {nil, as_prefix ++ [?f | Integer.to_string(pos)], nil}

        {table, schema, prefix} ->
          name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
          {quote_table(prefix, table), name, schema}

        %Ecto.SubQuery{} ->
          {nil, as_prefix ++ [?s | Integer.to_string(pos)], nil}
      end
    end

    defp create_alias(<<first, _rest::binary>>) when first in ?a..?z when first in ?A..?Z do
      first
    end
    defp create_alias(_) do
      ?t
    end

    # DDL

    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    @creates [:create, :create_if_not_exists]
    @drops [:drop, :drop_if_exists]

    @impl true
    def execute_ddl({command, %Table{} = table, columns}) when command in @creates do
      table_name = quote_table(table.prefix, table.name)
      query = ["CREATE TABLE ",
               if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
               table_name, ?\s, ?(,
               column_definitions(table, columns), pk_definition(columns, ", "), ?),
               options_expr(table.options)]

      [query] ++
        comments_on("TABLE", table_name, table.comment) ++
        comments_for_columns(table_name, columns)
    end

    def execute_ddl({command, %Table{} = table}) when command in @drops do
      [["DROP TABLE ", if_do(command == :drop_if_exists, "IF EXISTS "),
        quote_table(table.prefix, table.name)]]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      table_name = quote_table(table.prefix, table.name)
      query = ["ALTER TABLE ", table_name, ?\s,
               column_changes(table, changes), pk_definition(changes, ", ADD ")]

      [query] ++
        comments_on("TABLE", table_name, table.comment) ++
        comments_for_columns(table_name, changes)
    end

    def execute_ddl({command, %Index{} = index}) when command in @creates do
      fields = intersperse_map(index.columns, ", ", &index_expr/1)
      include_fields = intersperse_map(index.include, ", ", &index_expr/1)

      queries = [["CREATE ",
                  if_do(index.unique, "UNIQUE "),
                  "INDEX ",
                  if_do(index.concurrently, "CONCURRENTLY "),
                  if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
                  quote_name(index.name),
                  " ON ",
                  quote_table(index.prefix, index.table),
                  if_do(index.using, [" USING " , to_string(index.using)]),
                  ?\s, ?(, fields, ?),
                  if_do(include_fields != [], [" INCLUDE ", ?(, include_fields, ?)]),
                  if_do(index.where, [" WHERE ", to_string(index.where)])]]

      queries ++ comments_on("INDEX", quote_table(index.prefix, index.name), index.comment)
    end

    def execute_ddl({command, %Index{} = index}) when command in @drops do
      [["DROP INDEX ",
        if_do(index.concurrently, "CONCURRENTLY "),
        if_do(command == :drop_if_exists, "IF EXISTS "),
        quote_table(index.prefix, index.name)]]
    end

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [["ALTER TABLE ", quote_table(current_table.prefix, current_table.name),
        " RENAME TO ", quote_table(nil, new_table.name)]]
    end

    def execute_ddl({:rename, %Table{} = table, current_column, new_column}) do
      [["ALTER TABLE ", quote_table(table.prefix, table.name), " RENAME ",
        quote_name(current_column), " TO ", quote_name(new_column)]]
    end

    def execute_ddl({:create, %Constraint{} = constraint}) do
      table_name = quote_table(constraint.prefix, constraint.table)
      queries = [["ALTER TABLE ", table_name,
                  " ADD ", new_constraint_expr(constraint)]]

      queries ++ comments_on("CONSTRAINT", constraint.name, constraint.comment, table_name)
    end

    def execute_ddl({:drop, %Constraint{} = constraint}) do
      [["ALTER TABLE ", quote_table(constraint.prefix, constraint.table),
        " DROP CONSTRAINT ", quote_name(constraint.name)]]
    end

    def execute_ddl({:drop_if_exists, %Constraint{} = constraint}) do
      [["ALTER TABLE ", quote_table(constraint.prefix, constraint.table),
        " DROP CONSTRAINT IF EXISTS ", quote_name(constraint.name)]]
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in execute")

    @impl true
    def ddl_logs(%Postgrex.Result{} = result) do
      %{messages: messages} = result

      for message <- messages do
        %{message: message, severity: severity} = message

        {ddl_log_level(severity), message, []}
      end
    end

    @impl true
    def table_exists_query(table) do
      {"SELECT true FROM information_schema.tables WHERE table_name = $1 AND table_schema = current_schema() LIMIT 1", [table]}
    end

    # From https://www.postgresql.org/docs/current/protocol-error-fields.html.
    defp ddl_log_level("DEBUG"), do: :debug
    defp ddl_log_level("LOG"), do: :info
    defp ddl_log_level("INFO"), do: :info
    defp ddl_log_level("NOTICE"), do: :info
    defp ddl_log_level("WARNING"), do: :warn
    defp ddl_log_level("ERROR"), do: :error
    defp ddl_log_level("FATAL"), do: :error
    defp ddl_log_level("PANIC"), do: :error
    defp ddl_log_level(_severity), do: :info

    defp pk_definition(columns, prefix) do
      pks =
        for {_, name, _, opts} <- columns,
            opts[:primary_key],
            do: name

      case pks do
        [] -> []
        _  -> [prefix, "PRIMARY KEY (", quote_names(pks), ")"]
      end
    end

    defp comments_on(_object, _name, nil), do: []
    defp comments_on(object, name, comment) do
      [["COMMENT ON ", object, ?\s, name, " IS ", single_quote(comment)]]
    end

    defp comments_on(_object, _name, nil, _table_name), do:  []
    defp comments_on(object, name, comment, table_name) do
      [["COMMENT ON ", object, ?\s, quote_name(name), " ON ", table_name,
        " IS ", single_quote(comment)]]
    end

    defp comments_for_columns(table_name, columns) do
      Enum.flat_map(columns, fn
        {_operation, column_name, _column_type, opts} ->
          column_name = [table_name, ?. | quote_name(column_name)]
          comments_on("COLUMN", column_name, opts[:comment])
        _ -> []
      end)
    end

    defp column_definitions(table, columns) do
      intersperse_map(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(ref.type, opts), ", ", reference_expr(ref, table, name)]
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      [quote_name(name), ?\s, column_type(type, opts), column_options(type, opts)]
    end

    defp column_changes(table, columns) do
      intersperse_map(columns, ", ", &column_change(table, &1))
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      ["ADD COLUMN ", quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(ref.type, opts), ", ADD ", reference_expr(ref, table, name)]
    end

    defp column_change(_table, {:add, name, type, opts}) do
      ["ADD COLUMN ", quote_name(name), ?\s, column_type(type, opts),
       column_options(type, opts)]
    end

    defp column_change(table, {:add_if_not_exists, name, %Reference{} = ref, opts}) do
      ["ADD COLUMN IF NOT EXISTS ", quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(ref.type, opts), ", ADD ", reference_expr(ref, table, name)]
    end

    defp column_change(_table, {:add_if_not_exists, name, type, opts}) do
      ["ADD COLUMN IF NOT EXISTS ", quote_name(name), ?\s, column_type(type, opts),
       column_options(type, opts)]
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      [drop_reference_expr(opts[:from], table, name), "ALTER COLUMN ", quote_name(name),
      " TYPE ", reference_column_type(ref.type, opts),
       ", ADD ", reference_expr(ref, table, name),
       modify_null(name, opts), modify_default(name, ref.type, opts)]
    end

    defp column_change(table, {:modify, name, type, opts}) do
      [drop_reference_expr(opts[:from], table, name), "ALTER COLUMN ", quote_name(name), " TYPE ",
       column_type(type, opts), modify_null(name, opts), modify_default(name, type, opts)]
    end

    defp column_change(_table, {:remove, name}), do: ["DROP COLUMN ", quote_name(name)]
    defp column_change(table, {:remove, name, %Reference{} = ref, _opts}) do
      [drop_reference_expr(ref, table, name), "DROP COLUMN ", quote_name(name)]
    end
    defp column_change(_table, {:remove, name, _type, _opts}), do: ["DROP COLUMN ", quote_name(name)]

    defp column_change(table, {:remove_if_exists, name, %Reference{} = ref}) do
      [drop_reference_if_exists_expr(ref, table, name), "DROP COLUMN IF EXISTS ", quote_name(name)]
    end
    defp column_change(_table, {:remove_if_exists, name, _type}), do: ["DROP COLUMN IF EXISTS ", quote_name(name)]

    defp modify_null(name, opts) do
      case Keyword.get(opts, :null) do
        true  -> [", ALTER COLUMN ", quote_name(name), " DROP NOT NULL"]
        false -> [", ALTER COLUMN ", quote_name(name), " SET NOT NULL"]
        nil   -> []
      end
    end

    defp modify_default(name, type, opts) do
      case Keyword.fetch(opts, :default) do
        {:ok, val} -> [", ALTER COLUMN ", quote_name(name), " SET", default_expr({:ok, val}, type)]
        :error -> []
      end
    end

    defp column_options(type, opts) do
      default = Keyword.fetch(opts, :default)
      null    = Keyword.get(opts, :null)

      [default_expr(default, type), null_expr(null)]
    end

    defp null_expr(false), do: " NOT NULL"
    defp null_expr(true), do: " NULL"
    defp null_expr(_), do: []

    defp new_constraint_expr(%Constraint{check: check} = constraint) when is_binary(check) do
      ["CONSTRAINT ", quote_name(constraint.name), " CHECK (", check, ")", validate(constraint.validate)]
    end
    defp new_constraint_expr(%Constraint{exclude: exclude} = constraint) when is_binary(exclude) do
      ["CONSTRAINT ", quote_name(constraint.name), " EXCLUDE USING ", exclude, validate(constraint.validate)]
    end

    defp default_expr({:ok, nil}, _type),    do: " DEFAULT NULL"
    defp default_expr({:ok, literal}, type), do: [" DEFAULT ", default_type(literal, type)]
    defp default_expr(:error, _),            do: []

    defp default_type(list, {:array, inner} = type) when is_list(list) do
      ["ARRAY[",  Enum.map(list, &default_type(&1, inner)) |> Enum.intersperse(?,), "]::", ecto_to_db(type)]
    end
    defp default_type(literal, _type) when is_binary(literal) do
      if :binary.match(literal, <<0>>) == :nomatch and String.valid?(literal) do
        single_quote(literal)
      else
        encoded = "\\x" <> Base.encode16(literal, case: :lower)
        raise ArgumentError, "default values are interpolated as UTF-8 strings and cannot contain null bytes. " <>
                             "`#{inspect literal}` is invalid. If you want to write it as a binary, use \"#{encoded}\", " <>
                             "otherwise refer to PostgreSQL documentation for instructions on how to escape this SQL type"
      end
    end
    defp default_type(literal, _type) when is_number(literal),  do: to_string(literal)
    defp default_type(literal, _type) when is_boolean(literal), do: to_string(literal)
    defp default_type(%{} = map, :map) do
      library = Application.get_env(:postgrex, :json_library, Jason)
      default = IO.iodata_to_binary(library.encode_to_iodata!(map))
      [single_quote(default)]
    end
    defp default_type({:fragment, expr}, _type),
      do: [expr]
    defp default_type(expr, type),
      do: raise(ArgumentError, "unknown default `#{inspect expr}` for type `#{inspect type}`. " <>
                               ":default may be a string, number, boolean, list of strings, list of integers, map (when type is Map), or a fragment(...)")

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal),
      do: quote_name(literal)

    defp options_expr(nil),
      do: []
    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in :options")
    defp options_expr(options),
      do: [?\s, options]

    defp column_type({:array, type}, opts),
      do: [column_type(type, opts), "[]"]

    defp column_type(type, _opts) when type in ~w(time utc_datetime naive_datetime)a,
      do: [ecto_to_db(type), "(0)"]

    defp column_type(type, opts) when type in ~w(time_usec utc_datetime_usec naive_datetime_usec)a do
      precision = Keyword.get(opts, :precision)
      type_name = ecto_to_db(type)

      if precision do
        [type_name, ?(, to_string(precision), ?)]
      else
        type_name
      end
    end

    defp column_type(:identity, opts) do
      start_value = [Keyword.get(opts, :start_value)]
      increment   = [Keyword.get(opts, :increment)]
      type_name   = ecto_to_db(:identity)

      cleanup = fn v -> is_integer(v) and v > 0 end

      sequence =
        start_value
        |> Enum.filter(cleanup)
        |> Enum.map(&"START WITH #{&1}")
        |> Kernel.++(
          increment
          |> Enum.filter(cleanup)
          |> Enum.map(&"INCREMENT BY #{&1}")
        )

      case sequence do
        [] -> [type_name, " GENERATED BY DEFAULT AS IDENTITY"]
        _ ->  [type_name, " GENERATED BY DEFAULT AS IDENTITY(", Enum.join(sequence, " "), ") "]
      end
    end

    defp column_type(type, opts) do
      size      = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale     = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      cond do
        size            -> [type_name, ?(, to_string(size), ?)]
        precision       -> [type_name, ?(, to_string(precision), ?,, to_string(scale || 0), ?)]
        type == :string -> [type_name, "(255)"]
        true            -> type_name
      end
    end

    defp reference_expr(%Reference{} = ref, table, name) do
      {current_columns, reference_columns} = Enum.unzip([{name, ref.column} | ref.with])

      ["CONSTRAINT ", reference_name(ref, table, name), ?\s,
       "FOREIGN KEY (", quote_names(current_columns), ") REFERENCES ",
       quote_table(ref.prefix || table.prefix, ref.table), ?(, quote_names(reference_columns), ?),
       reference_match(ref.match), reference_on_delete(ref.on_delete),
       reference_on_update(ref.on_update), validate(ref.validate)]
    end

    defp drop_reference_expr(%Reference{} = ref, table, name),
      do: ["DROP CONSTRAINT ", reference_name(ref, table, name), ", "]
    defp drop_reference_expr(_, _, _),
      do: []

    defp drop_reference_if_exists_expr(%Reference{} = ref, table, name),
      do: ["DROP CONSTRAINT IF EXISTS ", reference_name(ref, table, name), ", "]
    defp drop_reference_if_exists_expr(_, _, _),
      do: []

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "integer"
    defp reference_column_type(:bigserial, _opts), do: "bigint"
    defp reference_column_type(:identity, _opts), do: "bigint"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(:restrict), do: " ON DELETE RESTRICT"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(:restrict), do: " ON UPDATE RESTRICT"
    defp reference_on_update(_), do: []

    defp reference_match(nil), do: []
    defp reference_match(:full), do: " MATCH FULL"
    defp reference_match(:simple), do: " MATCH SIMPLE"
    defp reference_match(:partial), do: " MATCH PARTIAL"

    defp validate(false), do: " NOT VALID"
    defp validate(_), do: []

    ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      {expr || expr(source, sources, query), name}
    end

    defp get_parent_sources_ix(query, as) do
      case query.aliases[@parent_as] do
        {%{aliases: %{^as => ix}}, sources} -> {ix, sources}
        {%{} = parent, _sources} -> get_parent_sources_ix(parent, as)
      end
    end

    defp quote_qualified_name(name, sources, ix) do
      {_, source, _} = elem(sources, ix)
      [source, ?. | quote_name(name)]
    end

    defp quote_names(names) do
      intersperse_map(names, ?,, &quote_name/1)
    end

    defp quote_name(name) when is_atom(name) do
      quote_name(Atom.to_string(name))
    end
    defp quote_name(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad field name #{inspect name}")
      end
      [?", name, ?"]
    end

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: [quote_table(prefix), ?., quote_table(name)]

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad table name #{inspect name}")
      end
      [?", name, ?"]
    end

    # TRUE, ON, or 1 to enable the option, and FALSE, OFF, or 0 to disable it
    defp quote_boolean(nil), do: nil
    defp quote_boolean(true), do: "TRUE"
    defp quote_boolean(false), do: "FALSE"
    defp quote_boolean(value), do: error!(nil, "bad boolean value #{value}")

    defp format_to_sql(:text), do: "FORMAT TEXT"
    defp format_to_sql(:map), do: "FORMAT JSON"
    defp format_to_sql(:yaml), do: "FORMAT YAML"

    defp single_quote(value), do: [?', escape_string(value), ?']

    defp intersperse_map(list, separator, mapper, acc \\ [])
    defp intersperse_map([], _separator, _mapper, acc),
      do: acc
    defp intersperse_map([elem], _separator, mapper, acc),
      do: [acc | mapper.(elem)]
    defp intersperse_map([elem | rest], separator, mapper, acc),
      do: intersperse_map(rest, separator, mapper, [acc, mapper.(elem), separator])

    defp intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])
    defp intersperse_reduce([], _separator, user_acc, _reducer, acc),
      do: {acc, user_acc}
    defp intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      {[acc | elem], user_acc}
    end
    defp intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
      {elem, user_acc} = reducer.(elem, user_acc)
      intersperse_reduce(rest, separator, user_acc, reducer, [acc, elem, separator])
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp escape_json_key(value) when is_binary(value) do
      value
      |> escape_string()
      |> :binary.replace("\"", "\\\"", [:global])
    end

    defp ecto_to_db({:array, t}),          do: [ecto_to_db(t), ?[, ?]]
    defp ecto_to_db(:id),                  do: "integer"
    defp ecto_to_db(:identity),            do: "bigint"
    defp ecto_to_db(:serial),              do: "serial"
    defp ecto_to_db(:bigserial),           do: "bigserial"
    defp ecto_to_db(:binary_id),           do: "uuid"
    defp ecto_to_db(:string),              do: "varchar"
    defp ecto_to_db(:binary),              do: "bytea"
    defp ecto_to_db(:map),                 do: Application.fetch_env!(:ecto_sql, :postgres_map_type)
    defp ecto_to_db({:map, _}),            do: Application.fetch_env!(:ecto_sql, :postgres_map_type)
    defp ecto_to_db(:time_usec),           do: "time"
    defp ecto_to_db(:utc_datetime),        do: "timestamp"
    defp ecto_to_db(:utc_datetime_usec),   do: "timestamp"
    defp ecto_to_db(:naive_datetime),      do: "timestamp"
    defp ecto_to_db(:naive_datetime_usec), do: "timestamp"
    defp ecto_to_db(atom) when is_atom(atom),  do: Atom.to_string(atom)
    defp ecto_to_db(type) do
      raise ArgumentError,
            "unsupported type `#{inspect(type)}`. The type can either be an atom, a string " <>
              "or a tuple of the form `{:map, t}` or `{:array, t}` where `t` itself follows the same conditions."
    end

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
