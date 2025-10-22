defmodule Ecto.Integration.ConstraintsTest do
  use ExUnit.Case, async: true

  import Ecto.Migrator, only: [up: 4]
  alias Ecto.Integration.PoolRepo

  defmodule CustomConstraintHandler do
    @behaviour Ecto.Adapters.SQL.Constraint

    @impl Ecto.Adapters.SQL.Constraint
    # An example of a custom handler a user might write
    def to_constraints(
          %Postgrex.Error{postgres: %{pg_code: "ZZ001", constraint: constraint}} = _err,
          _opts
        ) do
      # Assumes that all pg_codes of ZZ001 are check constraint,
      # which may or may not be realistic
      [check: constraint]
    end

    def to_constraints(err, opts) do
      # Falls back to default `ecto_sql` handler for all others
      Ecto.Adapters.Postgres.Connection.to_constraints(err, opts)
    end
  end

  defmodule ConstraintTableMigration do
    use Ecto.Migration

    @table table(:constraints_test)

    def change do
      create @table do
        add :price, :integer
        add :from, :integer
        add :to, :integer
      end
    end
  end

  defmodule CheckConstraintMigration do
    use Ecto.Migration

    @table table(:constraints_test)

    def change do
      create constraint(@table.name, "positive_price", check: "price > 0")
    end
  end

  defmodule ExclusionConstraintMigration do
    use Ecto.Migration

    @table table(:constraints_test)

    def change do
      create constraint(@table.name, :cannot_overlap,
               exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|
             )
    end
  end

  defmodule TriggerEmulatingConstraintMigration do
    use Ecto.Migration

    @table_name :constraints_test

    def up do
      function_sql = ~s"""
      CREATE OR REPLACE FUNCTION check_price_limit()
        RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.price + 1 > 100 THEN
          RAISE EXCEPTION SQLSTATE 'ZZ001'
            USING MESSAGE = 'price must be less than 100, got ' || NEW.price::TEXT,
                  CONSTRAINT = 'price_above_max';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """

      insert_trigger_sql = trigger_sql(@table_name, "INSERT")
      update_trigger_sql = trigger_sql(@table_name, "UPDATE")

      drop_triggers(@table_name)
      repo().query!(function_sql)
      repo().query!(insert_trigger_sql)
      repo().query!(update_trigger_sql)
    end

    def down do
      drop_triggers(@table_name)
    end

    # not a great example, but demonstrates the feature
    defp trigger_sql(table_name, before_type) do
      ~s"""
      CREATE TRIGGER #{table_name}_before_price_#{String.downcase(before_type)}
        BEFORE #{String.upcase(before_type)}
        ON #{table_name}
        FOR EACH ROW
      EXECUTE FUNCTION check_price_limit();
      """
    end

    defp drop_triggers(table_name) do
      repo().query!("DROP TRIGGER IF EXISTS #{table_name}_before_price_insert ON #{table_name}")
      repo().query!("DROP TRIGGER IF EXISTS #{table_name}_before_price_update ON #{table_name}")
    end
  end

  defmodule Constraint do
    use Ecto.Integration.Schema

    schema "constraints_test" do
      field :price, :integer
      field :from, :integer
      field :to, :integer
    end
  end

  @base_migration 2_000_000

  setup_all do
    ExUnit.CaptureLog.capture_log(fn ->
      num = @base_migration + System.unique_integer([:positive])
      up(PoolRepo, num, ConstraintTableMigration, log: false)
    end)

    :ok
  end

  test "exclusion constraint" do
    num = @base_migration + System.unique_integer([:positive])

    ExUnit.CaptureLog.capture_log(fn ->
      :ok = up(PoolRepo, num, ExclusionConstraintMigration, log: false)
    end)

    changeset = Ecto.Changeset.change(%Constraint{}, from: 0, to: 10)
    {:ok, _} = PoolRepo.insert(changeset)

    non_overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 11, to: 12)
    {:ok, _} = PoolRepo.insert(non_overlapping_changeset)

    overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 9, to: 12)

    exception =
      assert_raise Ecto.ConstraintError,
                   ~r/constraint error when attempting to insert struct/,
                   fn ->
                     PoolRepo.insert(overlapping_changeset)
                   end

    assert exception.message =~ "\"cannot_overlap\" (exclusion_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `exclusion_constraint/3`"

    message = ~r/constraint error when attempting to insert struct/

    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        overlapping_changeset
        |> Ecto.Changeset.exclusion_constraint(:from)
        |> PoolRepo.insert()
      end

    assert exception.message =~ "\"cannot_overlap\" (exclusion_constraint)"

    {:error, changeset} =
      overlapping_changeset
      |> Ecto.Changeset.exclusion_constraint(:from, name: :cannot_overlap)
      |> PoolRepo.insert()

    assert changeset.errors == [
             from:
               {"violates an exclusion constraint",
                [constraint: :exclusion, constraint_name: "cannot_overlap"]}
           ]

    assert changeset.data.__meta__.state == :built
  end

  test "check constraint" do
    num = @base_migration + System.unique_integer([:positive])

    ExUnit.CaptureLog.capture_log(fn ->
      :ok = up(PoolRepo, num, CheckConstraintMigration, log: false)
    end)

    # When the changeset doesn't expect the db error
    changeset = Ecto.Changeset.change(%Constraint{}, price: -10)

    exception =
      assert_raise Ecto.ConstraintError,
                   ~r/constraint error when attempting to insert struct/,
                   fn -> PoolRepo.insert(changeset) end

    assert exception.message =~ "\"positive_price\" (check_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `check_constraint/3`"

    # When the changeset does expect the db error, but doesn't give a custom message
    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price)
      |> PoolRepo.insert()

    assert changeset.errors == [
             price: {"is invalid", [constraint: :check, constraint_name: "positive_price"]}
           ]

    assert changeset.data.__meta__.state == :built

    # When the changeset does expect the db error and gives a custom message
    changeset = Ecto.Changeset.change(%Constraint{}, price: -10)

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price,
        name: :positive_price,
        message: "price must be greater than 0"
      )
      |> PoolRepo.insert()

    assert changeset.errors == [
             price:
               {"price must be greater than 0",
                [constraint: :check, constraint_name: "positive_price"]}
           ]

    assert changeset.data.__meta__.state == :built

    # When the change does not violate the check constraint
    changeset = Ecto.Changeset.change(%Constraint{}, price: 10, from: 100, to: 200)

    {:ok, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price,
        name: :positive_price,
        message: "price must be greater than 0"
      )
      |> PoolRepo.insert()

    assert is_integer(changeset.id)
  end

  @tag :constraint_handler
  test "custom handled constraint" do
    num = @base_migration + System.unique_integer([:positive])

    ExUnit.CaptureLog.capture_log(fn ->
      :ok = up(PoolRepo, num, TriggerEmulatingConstraintMigration, log: false)
    end)

    changeset = Ecto.Changeset.change(%Constraint{}, price: 99, from: 201, to: 202)
    {:ok, item} = PoolRepo.insert(changeset)

    above_max_changeset = Ecto.Changeset.change(%Constraint{}, price: 100)

    msg_re = ~r/constraint error when attempting to insert struct/

    # When the changeset doesn't expect the db error
    exception =
      assert_raise Ecto.ConstraintError, msg_re, fn -> PoolRepo.insert(above_max_changeset) end

    assert exception.message =~ "\"price_above_max\" (check_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `check_constraint/3`"

    # When the changeset does expect the db error, but doesn't give a custom message
    {:error, changeset} =
      above_max_changeset
      |> Ecto.Changeset.check_constraint(:price, name: :price_above_max)
      |> PoolRepo.insert()

    assert changeset.errors == [
             price: {"is invalid", [constraint: :check, constraint_name: "price_above_max"]}
           ]

    assert changeset.data.__meta__.state == :built

    # When the changeset does expect the db error and gives a custom message
    {:error, changeset} =
      above_max_changeset
      |> Ecto.Changeset.check_constraint(:price,
        name: :price_above_max,
        message: "must be less than the max price"
      )
      |> PoolRepo.insert()

    assert changeset.errors == [
             price:
               {"must be less than the max price",
                [constraint: :check, constraint_name: "price_above_max"]}
           ]

    assert changeset.data.__meta__.state == :built

    # When the changeset does expect the db error, but a different handler is used
    exception =
      assert_raise Postgrex.Error, fn ->
        above_max_changeset
        |> Ecto.Changeset.check_constraint(:price, name: :price_above_max)
        |> PoolRepo.insert(
          constraint_handler: {Ecto.Adapters.Postgres.Connection, :to_constraints, []}
        )
      end

    # Just raises as-is
    assert exception.postgres.message == "price must be less than 100, got 100"

    # When custom error is coming from an UPDATE
    above_max_update_changeset = Ecto.Changeset.change(item, price: 100)

    {:error, changeset} =
      above_max_update_changeset
      |> Ecto.Changeset.check_constraint(:price,
        name: :price_above_max,
        message: "must be less than the max price"
      )
      |> PoolRepo.insert()

    assert changeset.errors == [
             price:
               {"must be less than the max price",
                [constraint: :check, constraint_name: "price_above_max"]}
           ]

    assert changeset.data.__meta__.state == :loaded
  end
end
