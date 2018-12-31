defmodule EctoSQL.MixProject do
  use Mix.Project

  @version "3.0.4"
  @adapters ~w(pg mysql)

  def project do
    [
      app: :ecto_sql,
      version: @version,
      elixir: "~> 1.4",
      deps: deps(),
      test_paths: test_paths(System.get_env("ECTO_ADAPTER")),
      xref: [
        exclude: [
          Mariaex,
          Ecto.Adapters.MySQL.Connection,
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
      {:ecto, "~> 3.0.6", ecto_opts()},
      {:telemetry, "~> 0.3.0"},

      # Drivers
      {:db_connection, "~> 2.0"},
      {:postgrex, "~> 0.14.0", optional: true},
      {:mariaex, "~> 0.9.1", optional: true},

      # Bring something in for JSON during tests
      {:jason, ">= 0.0.0", only: :test},

      # Docs
      {:ex_doc, "~> 0.19", only: :docs},

      # Benchmarks
      {:benchee, "~> 0.11.0", only: :bench},
      {:benchee_json, "~> 0.4.0", only: :bench}
    ]
  end

  defp ecto_opts do
    if path = System.get_env("ECTO_PATH") do
      [path: path]
    else
      []
    end
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(_), do: ["test"]

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache 2.0"],
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
          Ecto.Adapters.MySQL,
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
