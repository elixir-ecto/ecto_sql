defmodule Ecto.Integration.ConstraintsTest do
  use ExUnit.Case, async: true

  import Ecto.Migrator, only: [up: 4]
  alias Ecto.Integration.PoolRepo

  defmodule CustomConstraintHandler do
    @behaviour Ecto.Adapters.SQL.Constraint

    @quotes ~w(" ' `)

    @impl Ecto.Adapters.SQL.Constraint
    # An example of a custom handler a user might write
    def to_constraints(%MyXQL.Error{mysql: %{name: :ER_SIGNAL_EXCEPTION}, message: message}, opts) do
      # Assumes this is the only use-case of `ER_SIGNAL_EXCEPTION` the user has implemented custom errors for
      with [_, quoted] <- :binary.split(message, "Overlapping values for key "),
           [_, index | _] <- :binary.split(quoted, @quotes, [:global]) do
        [exclusion: strip_source(index, opts[:source])]
      else
        _ -> []
      end
    end

    def to_constraints(err, opts) do
      # Falls back to default `ecto_sql` handler for all others
      Ecto.Adapters.MyXQL.Connection.to_constraints(err, opts)
    end

    defp strip_source(name, nil), do: name
    defp strip_source(name, source), do: String.trim_leading(name, "#{source}.")
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
      # Only valid after MySQL 8.0.19
      create constraint(@table.name, :positive_price, check: "price > 0")
    end
  end

  defmodule TriggerEmulatingConstraintMigration do
    use Ecto.Migration

    @table_name :constraints_test

    def up do
      insert_trigger_sql = trigger_sql(@table_name, "INSERT")
      update_trigger_sql = trigger_sql(@table_name, "UPDATE")

      drop_triggers(@table_name)
      repo().query!(insert_trigger_sql)
      repo().query!(update_trigger_sql)
    end

    def down do
      drop_triggers(@table_name)
    end

    # FOR EACH ROW, not a great example performance-wise,
    # but demonstrates the feature
    defp trigger_sql(table_name, before_type) do
      ~s"""
      CREATE TRIGGER #{table_name}_#{String.downcase(before_type)}_overlap
        BEFORE #{String.upcase(before_type)}
        ON #{table_name}
        FOR EACH ROW
      BEGIN
        DECLARE v_rowcount INT;
        DECLARE v_msg VARCHAR(200);

        SELECT COUNT(*) INTO v_rowcount FROM #{table_name}
        WHERE (NEW.from <= `to` AND NEW.to >= `from`);

        IF v_rowcount > 0 THEN
            SET v_msg = CONCAT('Overlapping values for key \\'#{table_name}.cannot_overlap\\'');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg, MYSQL_ERRNO = 1644;
        END IF;
      END;
      """
    end

    defp drop_triggers(table_name) do
      repo().query!("DROP TRIGGER IF EXISTS #{table_name}_insert_overlap")
      repo().query!("DROP TRIGGER IF EXISTS #{table_name}_update_overlap")
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

  @tag :create_constraint
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

    {:ok, result} =
      changeset
      |> Ecto.Changeset.check_constraint(:price,
        name: :positive_price,
        message: "price must be greater than 0"
      )
      |> PoolRepo.insert()

    assert is_integer(result.id)
  end

  @tag :constraint_handler
  test "custom handled constraint" do
    num = @base_migration + System.unique_integer([:positive])

    ExUnit.CaptureLog.capture_log(fn ->
      :ok = up(PoolRepo, num, TriggerEmulatingConstraintMigration, log: false)
    end)

    changeset = Ecto.Changeset.change(%Constraint{}, from: 0, to: 10)
    {:ok, item} = PoolRepo.insert(changeset)

    non_overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 11, to: 12)
    {:ok, _} = PoolRepo.insert(non_overlapping_changeset)

    overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 9, to: 12)

    msg_re = ~r/constraint error when attempting to insert struct/

    # When the changeset doesn't expect the db error
    exception =
      assert_raise Ecto.ConstraintError, msg_re, fn -> PoolRepo.insert(overlapping_changeset) end

    assert exception.message =~ "\"cannot_overlap\" (exclusion_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `exclusion_constraint/3`"

    # When the changeset does expect the db error
    # but the key does not match the default generated by `exclusion_constraint`
    exception =
      assert_raise Ecto.ConstraintError, msg_re, fn ->
        overlapping_changeset
        |> Ecto.Changeset.exclusion_constraint(:from)
        |> PoolRepo.insert()
      end

    assert exception.message =~ "\"cannot_overlap\" (exclusion_constraint)"

    # When the changeset does expect the db error, but doesn't give a custom message
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

    # When the changeset does expect the db error and gives a custom message
    {:error, changeset} =
      overlapping_changeset
      |> Ecto.Changeset.exclusion_constraint(:from,
        name: :cannot_overlap,
        message: "must not overlap"
      )
      |> PoolRepo.insert()

    assert changeset.errors == [
             from:
               {"must not overlap", [constraint: :exclusion, constraint_name: "cannot_overlap"]}
           ]

    assert changeset.data.__meta__.state == :built

    # When the changeset does expect the db error, but a different handler is used
    exception =
      assert_raise MyXQL.Error, fn ->
        overlapping_changeset
        |> Ecto.Changeset.exclusion_constraint(:from, name: :cannot_overlap)
        |> PoolRepo.insert(
          constraint_handler: {Ecto.Adapters.MyXQL.Connection, :to_constraints, []}
        )
      end

    assert exception.message =~ "Overlapping values for key 'constraints_test.cannot_overlap'"

    # When custom error is coming from an UPDATE
    overlapping_update_changeset = Ecto.Changeset.change(item, from: 0, to: 9)

    {:error, changeset} =
      overlapping_update_changeset
      |> Ecto.Changeset.exclusion_constraint(:from,
        name: :cannot_overlap,
        message: "must not overlap"
      )
      |> PoolRepo.insert()

    assert changeset.errors == [
             from:
               {"must not overlap", [constraint: :exclusion, constraint_name: "cannot_overlap"]}
           ]

    assert changeset.data.__meta__.state == :loaded
  end
end
