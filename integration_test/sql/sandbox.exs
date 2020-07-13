defmodule Ecto.Integration.SandboxTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Integration.{PoolRepo, TestRepo}
  alias Ecto.Integration.Post

  import ExUnit.CaptureLog

  describe "errors" do
    test "raises if repo is not started or not exist" do
      assert_raise RuntimeError, ~r"could not lookup Ecto repo UnknownRepo because it was not started", fn ->
        Sandbox.mode(UnknownRepo, :manual)
      end
    end

    test "raises if repo is not using sandbox" do
      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.mode(PoolRepo, :manual)
      end

      assert_raise RuntimeError, ~r"cannot invoke sandbox operation with pool DBConnection", fn ->
        Sandbox.checkout(PoolRepo)
      end
    end

    test "includes link to SQL sandbox on ownership errors" do
      assert_raise DBConnection.OwnershipError,
               ~r"See Ecto.Adapters.SQL.Sandbox docs for more information.", fn ->
        TestRepo.all(Post)
      end
    end
  end

  describe "mode" do
    test "uses the repository when checked out" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end
      Sandbox.checkout(TestRepo)
      assert TestRepo.all(Post) == []
      Sandbox.checkin(TestRepo)
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end
    end

    test "uses the repository when allowed from another process" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.allow(TestRepo, self(), parent)
        send(parent, :allowed)
        Process.sleep(:infinity)
      end

      assert_receive :allowed
      assert TestRepo.all(Post) == []
    end

    test "uses the repository when shared from another process" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link(fn ->
        Sandbox.checkout(TestRepo)
        Sandbox.mode(TestRepo, {:shared, self()})
        send(parent, :shared)
        Process.sleep(:infinity)
      end)

      assert_receive :shared
      assert Task.async(fn -> TestRepo.all(Post) end) |> Task.await == []
    after
      Sandbox.mode(TestRepo, :manual)
    end
  end

  describe "savepoints" do
    test "runs inside a sandbox that is rolled back on checkin" do
      Sandbox.checkout(TestRepo)
      assert TestRepo.insert(%Post{})
      assert TestRepo.all(Post) != []
      Sandbox.checkin(TestRepo)
      Sandbox.checkout(TestRepo)
      assert TestRepo.all(Post) == []
      Sandbox.checkin(TestRepo)
    end

    test "runs inside a sandbox that may be disabled" do
      Sandbox.checkout(TestRepo, sandbox: false)
      assert TestRepo.insert(%Post{})
      assert TestRepo.all(Post) != []
      Sandbox.checkin(TestRepo)

      Sandbox.checkout(TestRepo)
      assert {1, _} = TestRepo.delete_all(Post)
      Sandbox.checkin(TestRepo)

      Sandbox.checkout(TestRepo, sandbox: false)
      assert {1, _} = TestRepo.delete_all(Post)
      Sandbox.checkin(TestRepo)
    end

    test "runs inside a sandbox with caller data when preloading associations" do
      Sandbox.checkout(TestRepo)
      assert TestRepo.insert(%Post{})
      parent = self()

      Task.start_link fn ->
        Sandbox.allow(TestRepo, parent, self())
        assert [_] = TestRepo.all(Post) |> TestRepo.preload([:author, :comments])
        send parent, :success
      end

      assert_receive :success
    end

    test "runs inside a sidebox with custom ownership timeout" do
      :ok = Sandbox.checkout(TestRepo, ownership_timeout: 200)
      parent = self()

      assert capture_log(fn ->
        {:ok, pid} =
          Task.start(fn ->
            Sandbox.allow(TestRepo, parent, self())
            TestRepo.transaction(fn -> Process.sleep(500) end)
          end)

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, _, ^pid, _}, 1000
      end) =~ "it owned the connection for longer than 200ms"
    end

    test "does not taint the sandbox on query errors" do
      Sandbox.checkout(TestRepo)

      {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)
      {:error, _} = TestRepo.query("INVALID")
      {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)

      Sandbox.checkin(TestRepo)
    end
  end

  describe "transactions" do
    @tag :transaction_isolation
    test "with custom isolation level" do
      Sandbox.checkout(TestRepo, isolation: "READ UNCOMMITTED")

      # Setting it to the same level later on works
      TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")

      # Even inside a transaction
      TestRepo.transaction fn ->
        TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
      end
    end

    test "disconnects on transaction timeouts" do
      Sandbox.checkout(TestRepo)

      assert capture_log(fn ->
        {:error, :rollback} =
          TestRepo.transaction(fn -> Process.sleep(1000) end, timeout: 100)
      end) =~ "timed out"

      Sandbox.checkin(TestRepo)
    end
  end

  describe "checkouts" do
    test "with transaction inside checkout" do
      Sandbox.checkout(TestRepo)

      TestRepo.checkout(fn ->
        refute TestRepo.in_transaction?()
        TestRepo.transaction(fn ->
          assert TestRepo.in_transaction?()
        end)
        refute TestRepo.in_transaction?()
      end)
    end

    test "with checkout inside transaction" do
      Sandbox.checkout(TestRepo)

      TestRepo.transaction(fn ->
        assert TestRepo.in_transaction?()
        TestRepo.checkout(fn ->
          assert TestRepo.in_transaction?()
        end)
        assert TestRepo.in_transaction?()
      end)
    end
  end

  describe "start_owner!/2" do
    test "checks out the connection" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      owner = Sandbox.start_owner!(TestRepo)
      assert TestRepo.all(Post) == []

      :ok = Sandbox.stop_owner(owner)
      refute Process.alive?(owner)
    end

    test "can set shared mode" do
      assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
        TestRepo.all(Post)
      end

      parent = self()

      Task.start_link(fn ->
        owner = Sandbox.start_owner!(TestRepo, shared: true)
        send(parent, {:owner, owner})
        Process.sleep(:infinity)
      end)

      assert_receive {:owner, owner}
      assert TestRepo.all(Post) == []
      :ok = Sandbox.stop_owner(owner)
    after
      Sandbox.mode(TestRepo, :manual)
    end
  end
end
