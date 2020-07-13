defmodule Ecto.Integration.LockTest do
  # We can keep this test async as long as it
  # is the only one accessing the lock_test table.
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Integration.PoolRepo

  defmodule LockCounter do
    use Ecto.Schema

    schema "lock_counters" do
      field :count, :integer
    end
  end

  setup do
    PoolRepo.delete_all(LockCounter)
    :ok
  end

  test "hints for update" do
    %{id: id} = PoolRepo.insert!(%LockCounter{count: 1})
    pid = self()
    query = from(lc in LockCounter, hints: ["UPDLOCK"], where: lc.id == ^id)

    {:ok, new_pid} =
      Task.start_link fn ->
        assert_receive :select_for_update, 5000

        PoolRepo.transaction(fn ->
          [post] = PoolRepo.all(query) # this should block until the other trans. commit
          post |> Ecto.Changeset.change(count: post.count + 1) |> PoolRepo.update!
        end)

        send pid, :updated
      end

    PoolRepo.transaction(fn ->
      [post] = PoolRepo.all(query)       # select and lock the row
      send new_pid, :select_for_update   # signal second process to begin a transaction
      post |> Ecto.Changeset.change(count: post.count + 1) |> PoolRepo.update!
    end)

    assert_receive :updated, 5000

    # Final count will be 3 if SELECT ... FOR UPDATE worked and 2 otherwise
    assert [%LockCounter{count: 3}] = PoolRepo.all(LockCounter)
  end
end
