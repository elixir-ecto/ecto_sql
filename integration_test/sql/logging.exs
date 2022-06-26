defmodule Ecto.Integration.LoggingTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.{Post, Logging, ArrayLogging}

  import ExUnit.CaptureLog
  import Ecto.Query, only: [from: 2]

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

  describe "parameter logging" do
    @describetag :parameter_logging

    @uuid_regex ~r/[0-9a-f]{2}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    @naive_datetime_regex ~r/~N\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/

    test "for insert" do
      int = 1
      uuid = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          TestRepo.insert!(%Logging{uuid: uuid, int: int},
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<inserted_at>.+), (?<updated_at>.+), \"(?<bid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["inserted_at"] =~ @naive_datetime_regex
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] =~ @uuid_regex
    end

    @tag :with_conflict_target
    test "for insert with conflict query" do
      int = 1
      conflict_int = 0
      uuid = Ecto.UUID.generate()
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from(l in Logging,
          where: l.uuid == ^conflict_uuid and l.int == ^conflict_int,
          update: [set: [int: ^conflict_update]]
        )

      log =
        capture_log(fn ->
          TestRepo.insert!(%Logging{uuid: uuid, int: int},
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<inserted_at>.+), (?<updated_at>.+), \"(?<bid>.+)\", (?<conflict_update>.+), \"(?<conflict_uuid>.+)\", (?<conflict_int>.+)\]/

      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["inserted_at"] =~ @naive_datetime_regex
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] =~ @uuid_regex
      # Conflict query params
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    test "for update" do
      int = 1
      uuid = Ecto.UUID.generate()
      current = TestRepo.insert!(%Logging{})

      log =
        capture_log(fn ->
          TestRepo.update!(Ecto.Changeset.change(current, %{uuid: uuid, int: int}), log: :info)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<updated_at>.+), \"(?<bid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] == current.bid
    end

    test "for delete" do
      current = TestRepo.insert!(%Logging{})

      log =
        capture_log(fn ->
          TestRepo.delete!(current, log: :info)
        end)

      param_regex = ~r/\[\"(?<bid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # Filters
      assert param_logs["bid"] == current.bid
    end

    test "for queries" do
      int = 1
      uuid = Ecto.UUID.generate()

      # all
      log =
        capture_log(fn ->
          TestRepo.all(from(l in Logging, select: type(^"1", :integer), where: l.int == ^int and l.uuid == ^uuid), log: :info)
        end)

      param_regex = ~r/\[(?<tagged_int>.+), (?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["tagged_int"] == Integer.to_string(int)
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid

      # update_all
      update = 2

      log =
        capture_log(fn ->
          from(l in Logging,
            where: l.int == ^int and l.uuid == ^uuid,
            update: [set: [int: ^update]]
          )
          |> TestRepo.update_all([], log: :info)
        end)

      param_regex = ~r/\[(?<update>.+), (?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["update"] == Integer.to_string(update)
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid

      # delete_all
      log =
        capture_log(fn ->
          TestRepo.delete_all(from(l in Logging, where: l.int == ^int and l.uuid == ^uuid),
            log: :info
          )
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :stream
    test "for queries with stream" do
      int = 1
      uuid = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          stream =
            TestRepo.stream(from(l in Logging, where: l.int == ^int and l.uuid == ^uuid),
              log: :info
            )

          TestRepo.transaction(fn -> Enum.to_list(stream) end)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :array_type
    test "for queries with array type" do
      uuid = Ecto.UUID.generate()
      uuid2 = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          TestRepo.all(from(a in ArrayLogging, where: a.uuids == ^[uuid, uuid2]),
            log: :info
          )
        end)

      param_regex = ~r/\[(?<uuids>\[.+\])\]/
      param_logs = Regex.named_captures(param_regex, log)

      assert param_logs["uuids"] == "[\"#{uuid}\", \"#{uuid2}\"]"
    end
  end
end
