defmodule Ecto.Integration.ConstraintsTest do
  use ExUnit.Case, async: true

  import Ecto.Migrator, only: [up: 4]
  alias Ecto.Integration.PoolRepo

  defmodule ConstraintMigration do
    use Ecto.Migration

    @table table(:constraints_test)

    def change do
      create @table do
        add :price, :integer
        add :from, :integer
        add :to, :integer
      end

      # Only valid after MySQL 8.0.19
      create constraint(@table.name, :positive_price, check: "price > 0")
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
      up(PoolRepo, num, ConstraintMigration, log: false)
    end)

    :ok
  end

  test "check constraint" do
    # When the changeset doesn't expect the db error
    changeset = Ecto.Changeset.change(%Constraint{}, price: -10)
    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        PoolRepo.insert(changeset)
      end

    assert exception.message =~ "\"positive_price\" (check_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `check_constraint/3`"

    # When the changeset does expect the db error, but doesn't give a custom message
    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price)
      |> PoolRepo.insert()
    assert changeset.errors == [price: {"is invalid", [constraint: :check, constraint_name: "positive_price"]}]
    assert changeset.data.__meta__.state == :built

    # When the changeset does expect the db error and gives a custom message
    changeset = Ecto.Changeset.change(%Constraint{}, price: -10)
    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price, message: "price must be greater than 0")
      |> PoolRepo.insert()
    assert changeset.errors == [price: {"price must be greater than 0", [constraint: :check, constraint_name: "positive_price"]}]
    assert changeset.data.__meta__.state == :built

    # When the change does not violate the check constraint
    changeset = Ecto.Changeset.change(%Constraint{}, price: 10, from: 100, to: 200)
    {:ok, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price, message: "price must be greater than 0")
      |> PoolRepo.insert()
    assert is_integer(changeset.id)
  end
end
