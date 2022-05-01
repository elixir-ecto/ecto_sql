defmodule Ecto.Integration.LoggingTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.Post

  import ExUnit.CaptureLog

  describe "telemetry" do
    test "dispatches event" do
      log = fn event_name, measurements, metadata ->
        assert Enum.at(event_name, -1) == :query
        assert %{result: {:ok, _res}} = metadata

        assert measurements.total_time ==
                 measurements.query_time + measurements.decode_time + measurements.queue_time

        assert measurements.idle_time
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post)
      assert_received :logged
    end

    test "dispatches event with stacktrace" do
      log = fn _event_name, _measurements, metadata ->
        assert %{stacktrace: [_ | _]} = metadata
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, stacktrace: true)
      assert_received :logged
    end

    test "dispatches event with custom options" do
      log = fn event_name, _measurements, metadata ->
        assert Enum.at(event_name, -1) == :query
        assert metadata.options == [:custom_metadata]
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, telemetry_options: [:custom_metadata])
      assert_received :logged
    end

    test "dispatches under another event name" do
      log = fn [:custom], measurements, metadata ->
        assert %{result: {:ok, _res}} = metadata

        assert measurements.total_time ==
                 measurements.query_time + measurements.decode_time + measurements.queue_time

        assert measurements.idle_time
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      _ = PoolRepo.all(Post, telemetry_event: [:custom])
      assert_received :logged
    end

    test "is not dispatched with no event name" do
      Process.put(:telemetry, fn _, _ -> raise "never called" end)
      _ = TestRepo.all(Post, telemetry_event: nil)
      refute_received :logged
    end
  end

  describe "logs" do
    @stacktrace_opts [stacktrace: true, log: :error]

    defp stacktrace_entry(line) do
      "↳ anonymous fn/0 in Ecto.Integration.LoggingTest.\"test logs includes stacktraces\"/1, " <>
        "at: integration_test/sql/logging.exs:#{line - 3}"
    end

    test "when some measurements are nil" do
      assert capture_log(fn -> TestRepo.query("BEG", [], log: :error) end) =~
               "[error]"
    end

    test "includes stacktraces" do
      assert capture_log(fn ->
               TestRepo.all(Post, @stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               TestRepo.insert(%Post{}, @stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               # Test cascading options
               Ecto.Multi.new()
               |> Ecto.Multi.insert(:post, %Post{})
               |> TestRepo.transaction(@stacktrace_opts)

               :ok
             end) =~ stacktrace_entry(__ENV__.line)

      assert capture_log(fn ->
               # In theory we should point to the call _inside_ run
               # but all multi calls point to the transaction starting point.
               Ecto.Multi.new()
               |> Ecto.Multi.run(:all, fn _, _ -> {:ok, TestRepo.all(Post, @stacktrace_opts)} end)
               |> TestRepo.transaction()

               :ok
             end) =~ stacktrace_entry(__ENV__.line)
    end

    test "with custom log level" do
      assert capture_log(fn -> TestRepo.insert!(%Post{title: "1"}, log: :error) end) =~
               "[error]"

      # We cannot assert on the result because it depends on the suite log level
      capture_log(fn ->
        TestRepo.insert!(%Post{title: "1"}, log: true)
      end)

      # But this assertion is always true
      assert capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"}, log: false)
             end) == ""
    end
  end
end
