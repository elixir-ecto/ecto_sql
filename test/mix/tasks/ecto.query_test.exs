defmodule Mix.Tasks.Ecto.QueryTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Query, only: [run: 1]

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :text, :string
    end
  end

  defmodule Metadata do
    use Ecto.Schema

    embedded_schema do
      field :author, :string
      field :views, :integer
    end
  end

  defmodule Tag do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      field :secret, :string, redact: true
      field :inserted_at, :utc_datetime_usec
      embeds_one :metadata, Metadata
      embeds_many :tags, Tag
      has_many :comments, Comment
    end
  end

  test "runs a query against the repo in a read-only transaction" do
    Process.put(:test_repo_all_results, [
      [1, "first", "hunter2"],
      [2, "second", "swordfish"]
    ])

    in_tmp("read_only", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      run(["-r", to_string(__MODULE__.PostgresRepo), "from(p in Post)"])

      assert_received {:transaction, __MODULE__.PostgresRepo, _fun}
      assert_received {:query!, "SET TRANSACTION READ ONLY", [], opts}
      assert opts[:log] == false
      assert_received {:all, %Ecto.Query{}}
      assert_received {:mix_shell, :info, [output]}

      assert output =~ "%Mix.Tasks.Ecto.QueryTest.Post{"
      assert output =~ ~s(title: "first")
      refute output =~ "__meta__"
      refute output =~ "comments:"
      refute output =~ "secret:"
      refute output =~ "hunter2"
    end)
  end

  test "uses the configured default repo" do
    Application.put_env(:ecto_sql, :ecto_repos, [__MODULE__.PostgresRepo])
    on_exit(fn -> Application.delete_env(:ecto_sql, :ecto_repos) end)

    Process.put(:test_repo_all_results, [[1, "first", "hunter2"]])

    in_tmp("default_repo", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      run(["from(p in Post)"])

      assert_received {:query!, "SET TRANSACTION READ ONLY", [], _opts}
    end)
  end

  test "uses only aliases from .iex.exs" do
    Process.put(:test_repo_all_results, [[1, "first", "hunter2"]])

    in_tmp("dot_iex_aliases", fn ->
      File.write!(".iex.exs", """
      alias #{inspect(__MODULE__)}.{Post, Comment}
      Process.put(:dot_iex_was_evaluated, true)
      """)

      run(["-r", to_string(__MODULE__.PostgresRepo), "from(p in Post)"])

      refute Process.get(:dot_iex_was_evaluated)
      assert_received {:all, %Ecto.Query{}}
    end)
  end

  test "accepts a schema module queryable" do
    Process.put(:test_repo_all_results, [[1, "first", "hunter2"]])

    run(["-r", to_string(__MODULE__.PostgresRepo), inspect(Post)])

    assert_received {:all, %Ecto.Query{}}
    assert_received {:mix_shell, :info, [output]}
    assert output =~ ~s(title: "first")
  end

  test "limits printed entries" do
    Process.put(:test_repo_all_results, [
      [1, "first", "hunter2"],
      [2, "second", "swordfish"]
    ])

    in_tmp("limit", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      run(["-r", to_string(__MODULE__.PostgresRepo), "--limit", "1", "from(p in Post)"])

      assert_received {:all, %Ecto.Query{} = query}
      refute query.limit
      assert_received {:mix_shell, :info, [output]}
      assert output =~ ~s(title: "first")
      refute output =~ ~s(title: "second")
    end)
  end

  test "preserves query-level limits" do
    Process.put(:test_repo_all_results, [
      [1, "first", "hunter2"],
      [2, "second", "swordfish"]
    ])

    in_tmp("query_limit", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      run(["-r", to_string(__MODULE__.PostgresRepo), "from(p in Post, limit: 2)"])

      assert_received {:all, %Ecto.Query{} = query}
      assert inspect(query) =~ "limit: 2"
    end)
  end

  test "renders regular structs in schema fields" do
    inserted_at = ~U[2023-04-19 10:28:17.036648Z]
    Process.put(:test_repo_all_results, [[1, "first", "hunter2", inserted_at]])

    run(["-r", to_string(__MODULE__.PostgresRepo), inspect(Post)])

    assert_received {:mix_shell, :info, [output]}
    assert output =~ ~s(inserted_at: ~U[2023-04-19 10:28:17.036648Z])
  end

  test "renders embeds" do
    Process.put(:test_repo_all_results, [
      [1, "first", "hunter2", %Metadata{author: "mary", views: 3}, [%Tag{name: "elixir"}]]
    ])

    run(["-r", to_string(__MODULE__.PostgresRepo), inspect(Post)])

    assert_received {:mix_shell, :info, [output]}
    assert output =~ "metadata: %Mix.Tasks.Ecto.QueryTest.Metadata{"
    assert output =~ ~s(author: "mary")
    assert output =~ "views: 3"
    assert output =~ "tags: ["
    assert output =~ "%Mix.Tasks.Ecto.QueryTest.Tag{"
    assert output =~ ~s(name: "elixir")
  end

  test "does not change the default inspect function" do
    previous_fun = Inspect.Opts.default_inspect_fun()
    Process.put(:test_repo_all_results, [[1, "first", "hunter2"]])

    run(["-r", to_string(__MODULE__.PostgresRepo), inspect(Post)])

    assert Inspect.Opts.default_inspect_fun() == previous_fun
  end

  test "prints SQL and params with --sql" do
    Process.put(
      :test_repo_to_sql,
      {"SELECT p0.\"id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = $1)", [1]}
    )

    in_tmp("sql", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      run([
        "-r",
        to_string(__MODULE__.PostgresRepo),
        "--sql",
        "from(p in Post, where: p.id == ^1)"
      ])

      assert_received {:to_sql, :all, %Ecto.Query{}, []}
      refute_received {:all, _query}
      refute_received {:query!, "SET TRANSACTION READ ONLY", [], _opts}
      assert_received {:mix_shell, :info, [output]}

      assert output =~ ~s[SQL:\nSELECT p0."id" FROM "posts" AS p0 WHERE (p0."id" = $1)]
      assert output =~ "Params:\n[1]"
    end)
  end

  test "starts MySQL read-only transactions explicitly" do
    Process.put(:test_repo_all_results, [[1, "first", "hunter2"]])

    run(["-r", to_string(__MODULE__.MyXQLRepo), inspect(Post)])

    assert_received {:checkout, __MODULE__.MyXQLRepo}
    assert_received {:myxql_query!, "START TRANSACTION READ ONLY", [], opts}
    assert opts[:log] == false
    assert_received {:myxql_all, %Ecto.Query{}}
    assert_received {:myxql_query!, "ROLLBACK", [], rollback_opts}
    assert rollback_opts[:log] == false
    assert_received {:mix_shell, :info, [output]}
    assert output =~ ~s(title: "first")
  end

  test "prints MySQL SQL without starting a transaction" do
    Process.put(:test_repo_to_sql, {"SELECT p0.`id` FROM `posts` AS p0", []})

    run(["-r", to_string(__MODULE__.MyXQLRepo), "--sql", inspect(Post)])

    refute_received {:checkout, __MODULE__.MyXQLRepo}
    refute_received {:myxql_query!, "START TRANSACTION READ ONLY", [], _opts}
    refute_received {:myxql_query!, "ROLLBACK", [], _opts}
    assert_received {:myxql_to_sql, :all, %Ecto.Query{}, []}
    assert_received {:mix_shell, :info, [output]}
    assert output =~ ~s[SQL:\nSELECT p0.`id` FROM `posts` AS p0]
    assert output =~ "Params:\n[]"
  end

  test "raises when the evaluated expression is not queryable" do
    for query <- ["1", "%{}", "[]", ":ok"] do
      assert_raise Mix.Error,
                   ~r/Expected ecto\.query to evaluate to a queryable expression, got:/,
                   fn ->
                     run(["-r", to_string(__MODULE__.PostgresRepo), query])
                   end
    end
  end

  test "raises when multiple repos are given" do
    assert_raise Mix.Error,
                 "ecto.query found multiple repositories, please pass one with -r",
                 fn ->
                   run([
                     "-r",
                     to_string(__MODULE__.PostgresRepo),
                     "-r",
                     to_string(__MODULE__.PostgresRepo),
                     "from(p in Post)"
                   ])
                 end
  end

  test "raises when a query is not given" do
    assert_raise Mix.Error, "ecto.query expects a query to be given", fn ->
      run(["-r", to_string(__MODULE__.PostgresRepo)])
    end
  end

  test "raises when multiple queries are given" do
    assert_raise Mix.Error, "ecto.query expects a single query to be given", fn ->
      run(["-r", to_string(__MODULE__.PostgresRepo), inspect(Post), inspect(Post)])
    end
  end

  test "raises when limit is negative" do
    assert_raise Mix.Error,
                 "ecto.query expects --limit to be greater than or equal to zero",
                 fn ->
                   run(["-r", to_string(__MODULE__.PostgresRepo), "--limit", "-1", inspect(Post)])
                 end
  end

  test "raises when the adapter does not support read-only transactions" do
    assert_raise Mix.Error, ~r/read-only transactions.*Ecto.Adapters.Tds/s, fn ->
      run(["-r", to_string(__MODULE__.NoReadOnlyRepo), inspect(Post)])
    end
  end

  defmodule NoReadOnlyRepo do
    def __adapter__, do: Ecto.Adapters.Tds
  end

  defmodule PostgresRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    def transaction(fun, _opts \\ []) do
      send(self(), {:transaction, __MODULE__, fun})
      {:ok, fun.()}
    end

    def query!(sql, params \\ [], opts \\ []) do
      send(self(), {:query!, sql, params, opts})
      %{rows: [], num_rows: 0}
    end

    def all(query) do
      send(self(), {:all, query})

      rows = Process.get(:test_repo_all_results, [])

      Enum.map(rows, fn
        [id, title, secret] ->
          %Post{id: id, title: title, secret: secret}

        [id, title, secret, inserted_at] ->
          %Post{id: id, title: title, secret: secret, inserted_at: inserted_at}

        [id, title, secret, %Metadata{} = metadata, tags] ->
          %Post{id: id, title: title, secret: secret, metadata: metadata, tags: tags}
      end)
    end

    def to_sql(operation, queryable, opts \\ []) do
      send(self(), {:to_sql, operation, queryable, opts})
      Process.get(:test_repo_to_sql, {"SELECT s0.\"id\" FROM \"posts\" AS s0", []})
    end
  end

  defmodule MyXQLRepo do
    def __adapter__, do: Ecto.Adapters.MyXQL

    def checkout(fun, _opts \\ []) do
      send(test_process(), {:checkout, __MODULE__})
      fun.()
    end

    def query!(sql, params \\ [], opts \\ []) do
      send(test_process(), {:myxql_query!, sql, params, opts})
      %{rows: [], num_rows: 0}
    end

    def all(query) do
      send(test_process(), {:myxql_all, query})

      rows = Process.get(:test_repo_all_results, [])

      Enum.map(rows, fn [id, title, secret] ->
        %Post{id: id, title: title, secret: secret}
      end)
    end

    def to_sql(operation, queryable, opts \\ []) do
      send(test_process(), {:myxql_to_sql, operation, queryable, opts})
      Process.get(:test_repo_to_sql, {"SELECT p0.`id` FROM `posts` AS p0", []})
    end

    defp test_process do
      self()
    end
  end

  @tmp_path Path.expand("../../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, path)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, fun)
  end
end
