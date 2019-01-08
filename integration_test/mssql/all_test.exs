ecto = Mix.Project.deps_paths()[:ecto]
# Code.require_file "#{ecto}/integration_test/cases/assoc.exs", __DIR__
# Code.require_file "#{ecto}/integration_test/cases/interval.exs", __DIR__
# Code.require_file "#{ecto}/integration_test/cases/joins.exs", __DIR__
# Code.require_file "#{ecto}/integration_test/cases/preload.exs", __DIR__
# Code.require_file "#{ecto}/integration_test/cases/repo.exs", __DIR__
Code.require_file("#{ecto}/integration_test/cases/type.exs", __DIR__)

# Code.require_file "../sql/alter.exs", __DIR__
# Code.require_file "../sql/lock.exs", __DIR__
# Code.require_file "../sql/logging.exs", __DIR__
# Code.require_file "../sql/migration.exs", __DIR__
# Code.require_file "../sql/migrator.exs", __DIR__
# Code.require_file "../sql/sandbox.exs", __DIR__
# Code.require_file "../sql/sql.exs", __DIR__
# Code.require_file "../sql/stream.exs", __DIR__
# Code.require_file "../sql/subquery.exs", __DIR__
# Code.require_file "../sql/transaction.exs", __DIR__
