defmodule EctoSQL.MixProject do
  use Mix.Project

  @version "3.2.0"
  @adapters ~w(pg myxql)

  def project do
    [
      app: :ecto_sql,
      version: @version,
      elixir: "~> 1.6",
      deps: deps(),
      test_paths: test_paths(System.get_env("ECTO_ADAPTER")),
      xref: [
        exclude: [
          MyXQL,
          Ecto.Adapters.MyXQL.Connection,
          Postgrex,
          Ecto.Adapters.Postgres.Connection
        ]
      ],

      # Custom testing
      aliases: ["test.all": ["test", "test.adapters"], "test.adapters": &test_adapters/1],
      preferred_cli_env: ["test.all": :test, "test.adapters": :test],

      # Hex
      description: "SQL-based adapters for Ecto and database migrations",
      package: package(),

      # Docs
      name: "Ecto SQL",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [postgres_map_type: "jsonb"],
      mod: {Ecto.Adapters.SQL.Application, []}
    ]
  end

  defp deps do
    [
      ecto_dep(),
      {:telemetry, "~> 0.4.0"},

      # Drivers
      {:db_connection, "~> 2.1"},
      postgrex_dep(),
      myxql_dep(),

      # Bring something in for JSON during tests
      {:jason, ">= 0.0.0", only: [:test, :docs]},

      # Docs
      {:ex_doc, "~> 0.19", only: :docs},

      # Benchmarks
      {:benchee, "~> 0.11.0", only: :bench},
      {:benchee_json, "~> 0.4.0", only: :bench}
    ]
  end

  defp ecto_dep do
    if path = System.get_env("ECTO_PATH") do
      {:ecto, path: path}
    else
      {:ecto, "~> 3.2.0"}
    end
  end

  defp postgrex_dep do
    if path = System.get_env("POSTGREX_PATH") do
      {:postgrex, path: path}
    else
      {:postgrex, "~> 0.15.0", optional: true}
    end
  end

  defp myxql_dep do
    if path = System.get_env("MYXQL_PATH") do
      {:myxql, path: path}
    else
      {:myxql, "~> 0.2.0", optional: true}
    end
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(_), do: ["test"]

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/elixir-ecto/ecto_sql"},
      files:
        ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib) ++
          ~w(integration_test/sql integration_test/support)
    ]
  end

  defp test_adapters(args) do
    for adapter <- @adapters, do: env_run(adapter, args)
  end

  defp env_run(adapter, args) do
    args = if IO.ANSI.enabled?(), do: ["--color" | args], else: ["--no-color" | args]

    IO.puts("==> Running tests for ECTO_ADAPTER=#{adapter} mix test")

    {_, res} =
      System.cmd("mix", ["test" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"ECTO_ADAPTER", adapter}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp docs do
    [
      main: "Ecto.Adapters.SQL",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto_sql",
      source_url: "https://github.com/elixir-ecto/ecto_sql",
      groups_for_modules: [
        # Ecto.Adapters.SQL,
        # Ecto.Adapters.SQL.Sandbox,
        # Ecto.Migration,
        # Ecto.Migrator,

        "Built-in adapters": [
          Ecto.Adapters.MyXQL,
          Ecto.Adapters.Postgres
        ],
        "Adapter specification": [
          Ecto.Adapter.Migration,
          Ecto.Adapter.Structure,
          Ecto.Adapters.SQL.Connection,
          Ecto.Migration.Command,
          Ecto.Migration.Constraint,
          Ecto.Migration.Index,
          Ecto.Migration.Reference,
          Ecto.Migration.Table
        ]
      ]
    ]
  end
end
