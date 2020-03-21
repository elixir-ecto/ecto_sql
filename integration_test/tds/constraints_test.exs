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
      create constraint(@table.name, :cannot_overlap, check: "[from] < [to]")
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
    changeset = Ecto.Changeset.change(%Constraint{}, from: 0, to: 10)
    {:ok, _} = PoolRepo.insert(changeset)

    non_overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 11, to: 12)
    {:ok, _} = PoolRepo.insert(non_overlapping_changeset)

    overlapping_changeset = Ecto.Changeset.change(%Constraint{}, from: 1900, to: 12)

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        PoolRepo.insert(overlapping_changeset)
      end
    assert exception.message =~ "cannot_overlap (check_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `check_constraint/3`"

    {:error, changeset} =
      overlapping_changeset
      |> Ecto.Changeset.check_constraint(:from, name: :cannot_overlap)
      |> PoolRepo.insert()
    assert changeset.errors == [from: {"is invalid", [constraint: :check, constraint_name: "cannot_overlap"]}]
    assert changeset.data.__meta__.state == :built
  end
end
