defmodule Mix.Tasks.Ecto.Gen.MigrationTest do
  use ExUnit.Case, async: true

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Migration, only: [run: 1]

  tmp_path = Path.join(tmp_path(), inspect(Ecto.Gen.Migration))
  @migrations_path Path.join(tmp_path, "migrations")

  defmodule Repo do
    def __adapter__ do
      true
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Gen.Migration)}", otp_app: :ecto_sql]
    end
  end

  setup do
    File.rm_rf!(unquote(tmp_path))
    :ok
  end

  test "generates a new migration" do
    [path] = run(["-r", to_string(Repo), "my_migration"])
    assert Path.dirname(path) == @migrations_path
    assert Path.basename(path) =~ ~r/^\d{14}_my_migration\.exs$/

    assert_file(path, fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.MyMigration do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def change do"
    end)
  end

  test "generates a new migration with Custom Migration Module" do
    Application.put_env(:ecto_sql, :migration_module, MyCustomApp.MigrationModule)
    [path] = run(["-r", to_string(Repo), "my_custom_migration"])
    Application.delete_env(:ecto_sql, :migration_module)
    assert Path.dirname(path) == @migrations_path
    assert Path.basename(path) =~ ~r/^\d{14}_my_custom_migration\.exs$/

    assert_file(path, fn file ->
      assert file =~
               "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.MyCustomMigration do"

      assert file =~ "use MyCustomApp.MigrationModule"
      assert file =~ "def change do"
    end)
  end

  test "underscores the filename when generating a migration" do
    run(["-r", to_string(Repo), "MyMigration"])
    assert [name] = File.ls!(@migrations_path)
    assert name =~ ~r/^\d{14}_my_migration\.exs$/
  end

  test "converts spaces to underscores in migration name" do
    [path] = run(["-r", to_string(Repo), "add", "posts", "table"])
    assert Path.basename(path) =~ ~r/^\d{14}_add_posts_table\.exs$/

    assert_file(path, fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.AddPostsTable do"
    end)
  end

  test "handles multiple arguments as migration name components" do
    [path1] = run(["-r", to_string(Repo), "add", "posts", "table", "with", "index"])
    assert Path.basename(path1) =~ ~r/^\d{14}_add_posts_table_with_index\.exs$/

    [path2] = run(["-r", to_string(Repo), "create", "user", "accounts"])
    assert Path.basename(path2) =~ ~r/^\d{14}_create_user_accounts\.exs$/

    assert_file(path1, fn file ->
      assert file =~
               "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.AddPostsTableWithIndex do"
    end)

    assert_file(path2, fn file ->
      assert file =~
               "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.CreateUserAccounts do"
    end)
  end

  test "handles edge cases in migration name normalization" do
    [path] = run(["-r", to_string(Repo), "  add   posts   table  "])
    assert Path.basename(path) =~ ~r/^\d{14}_add_posts_table\.exs$/

    assert_file(path, fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.AddPostsTable do"
    end)
  end

  test "custom migrations_path" do
    dir = Path.join([unquote(tmp_path), "custom_migrations"])
    [path] = run(["-r", to_string(Repo), "--migrations-path", dir, "custom_path"])
    assert Path.dirname(path) == dir
  end

  test "raises when existing migration exists" do
    run(["-r", to_string(Repo), "my_migration"])

    assert_raise Mix.Error, ~r"migration can't be created", fn ->
      run(["-r", to_string(Repo), "my_migration"])
    end
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run(["-r", to_string(Repo)]) end
  end
end
