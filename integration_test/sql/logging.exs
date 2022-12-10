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

    test "cast params" do
      uuid_module =
        if TestRepo.__adapter__() == Ecto.Adapters.Tds do
          Tds.Ecto.UUID
        else
          Ecto.UUID
        end

      uuid = uuid_module.generate()
      dumped_uuid = uuid_module.dump!(uuid)

      log = fn _event_name, _measurements, metadata ->
        assert [dumped_uuid] == metadata.params
        assert [uuid] == metadata.cast_params
        send(self(), :logged)
      end

      Process.put(:telemetry, log)
      TestRepo.all(from l in Logging, where: l.uuid == ^uuid)
      assert_received :logged
    end
  end

  describe "logs" do
    @stacktrace_opts [stacktrace: true, log: :error]

    defp stacktrace_entry(line) do
      ~r/↳ anonymous fn\/0 in Ecto.Integration.LoggingTest.\"test logs includes stacktraces\"\/1, at: .*integration_test\/sql\/logging.exs:#{line - 3}/
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

    test "with a log: true override when logging is disabled" do
      refute capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"}, log: true)
             end) =~ "an exception was raised logging"
    end

    test "with unspecified :log option when logging is disabled" do
      refute capture_log(fn ->
               TestRepo.insert!(%Post{title: "1"})
             end) =~ "an exception was raised logging"
    end
  end

  describe "parameter logging" do
    @describetag :parameter_logging

    @uuid_regex ~r/[0-9a-f]{2}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    @naive_datetime_regex ~r/~N\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/

    test "for insert_all with query" do
      # Source query
      int = 1
      uuid = Ecto.UUID.generate()

      source_query =
        from l in Logging,
          where: l.int == ^int and l.uuid == ^uuid,
          select: %{uuid: l.uuid, int: l.int}

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, source_query, log: :info)
        end)

      param_regex = ~r/\[(?<int>.+), \"(?<uuid>.+)\"\]/
      param_logs = Regex.named_captures(param_regex, log)

      # Query parameters
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
    end

    @tag :insert_select
    test "for insert_all with entries" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: now,
        updated_at: now
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int
      now2 = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: now2,
        updated_at: now2
      ]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2], log: :info)
        end)

      param_regex =
        ~r/\[\"(?<bid1>.+)\", (?<inserted_at1>.+), (?<int1>.+), (?<updated_at1>.+), (?<uuid1_query_int>.+), \"(?<uuid1_query_uuid>.+)\", \"(?<bid2>.+)\", (?<inserted_at2>.+), (?<int2_query_int>.+), \"(?<int2_query_uuid>.+)\", (?<updated_at2>.+), \"(?<uuid2>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Autogenerated fields
      assert param_logs["bid1"] =~ @uuid_regex
      assert param_logs["bid2"] =~ @uuid_regex
      # Row value parameters
      assert param_logs["int1"] == Integer.to_string(int)
      assert param_logs["inserted_at1"] == "~N[#{now}]"
      assert param_logs["inserted_at2"] == "~N[#{now}]"
      assert param_logs["uuid1_query_int"] == Integer.to_string(int)
      assert param_logs["uuid1_query_uuid"] == uuid
      assert param_logs["int2_query_int"] == Integer.to_string(int2)
      assert param_logs["int2_query_uuid"] == uuid2
      assert param_logs["inserted_at2"] == "~N[#{now2}]"
      assert param_logs["updated_at2"] == "~N[#{now2}]"
      assert param_logs["uuid2"] == uuid2
    end

    @tag :insert_select
    @tag :placeholders
    test "for insert_all with entries and placeholders" do
      # Placeholders
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      now2 = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      placeholder_map = %{now: now, now2: now2}

      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now}
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: {:placeholder, :now2},
        updated_at: {:placeholder, :now2}
      ]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2], placeholders: placeholder_map, log: :info)
        end)

      param_regex =
        ~r/\[(?<now_placeholder>.+), (?<now2_placeholder>.+), \"(?<bid1>.+)\", (?<int1>.+), (?<uuid1_query_int>.+), \"(?<uuid1_query_uuid>.+)\", \"(?<bid2>.+)\", (?<int2_query_int>.+), \"(?<int2_query_uuid>.+)\", \"(?<uuid2>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Placeholders
      assert param_logs["now_placeholder"] == "~N[#{now}]"
      assert param_logs["now2_placeholder"] == "~N[#{now2}]"
      # Autogenerated fields
      assert param_logs["bid1"] =~ @uuid_regex
      assert param_logs["bid2"] =~ @uuid_regex
      # Row value parameters
      assert param_logs["int1"] == Integer.to_string(int)
      assert param_logs["uuid1_query_int"] == Integer.to_string(int)
      assert param_logs["uuid1_query_uuid"] == uuid
      assert param_logs["int2_query_int"] == Integer.to_string(int2)
      assert param_logs["int2_query_uuid"] == uuid2
      assert param_logs["uuid2"] == uuid2
    end

    @tag :with_conflict_target
    test "for insert_all with query with conflict query" do
      # Source query
      int = 1
      uuid = Ecto.UUID.generate()

      source_query =
        from l in Logging,
          where: l.int == ^int and l.uuid == ^uuid,
          select: %{uuid: l.uuid, int: l.int}

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, source_query,
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Query parameters
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    @tag :insert_select
    @tag :with_conflict_target
    test "for insert_all with entries conflict query" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: now,
        updated_at: now
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int
      now2 = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: now2,
        updated_at: now2
      ]

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2],
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[\"(?<bid1>.+)\", (?<inserted_at1>.+), (?<int1>.+), (?<updated_at1>.+), (?<uuid1_query_int>.+), \"(?<uuid1_query_uuid>.+)\", \"(?<bid2>.+)\", (?<inserted_at2>.+), (?<int2_query_int>.+), \"(?<int2_query_uuid>.+)\", (?<updated_at2>.+), \"(?<uuid2>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Autogenerated fields
      assert param_logs["bid1"] =~ @uuid_regex
      assert param_logs["bid2"] =~ @uuid_regex
      # Row value parameters
      assert param_logs["int1"] == Integer.to_string(int)
      assert param_logs["inserted_at1"] == "~N[#{now2}]"
      assert param_logs["updated_at1"] == "~N[#{now2}]"
      assert param_logs["uuid1_query_int"] == Integer.to_string(int)
      assert param_logs["uuid1_query_uuid"] == uuid
      assert param_logs["int2_query_int"] == Integer.to_string(int2)
      assert param_logs["int2_query_uuid"] == uuid2
      assert param_logs["inserted_at2"] == "~N[#{now2}]"
      assert param_logs["updated_at2"] == "~N[#{now2}]"
      assert param_logs["uuid2"] == uuid2
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    @tag :insert_select
    @tag :placeholders
    @tag :with_conflict_target
    test "for insert_all with entries, placeholders and conflict query" do
      # Row 1
      int = 1
      uuid = Ecto.UUID.generate()
      uuid_query = from l in Logging, where: l.int == ^int and l.uuid == ^uuid, select: l.uuid

      row1 = [
        int: int,
        uuid: uuid_query,
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now2}
      ]

      # Row 2
      int2 = 2
      uuid2 = Ecto.UUID.generate()
      int_query = from l in Logging, where: l.int == ^int2 and l.uuid == ^uuid2, select: l.int

      row2 = [
        int: int_query,
        uuid: uuid2,
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now2}
      ]

      # Placeholders
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      now2 = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      placeholder_map = %{now: now, now2: now2}

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert_all(Logging, [row1, row2],
            placeholders: placeholder_map,
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<now_placeholder>.+), (?<now2_placeholder>.+), \"(?<bid1>.+)\", (?<int1>.+), (?<uuid1_query_int>.+), \"(?<uuid1_query_uuid>.+)\", \"(?<bid2>.+)\", (?<int2_query_int>.+), \"(?<int2_query_uuid>.+)\", \"(?<uuid2>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # Placeholders
      assert param_logs["now_placeholder"] == "~N[#{now}]"
      assert param_logs["now2_placeholder"] == "~N[#{now2}]"
      # Autogenerated fields
      assert param_logs["bid1"] =~ @uuid_regex
      assert param_logs["bid2"] =~ @uuid_regex
      # Row value parameters
      assert param_logs["int1"] == Integer.to_string(int)
      assert param_logs["uuid1_query_int"] == Integer.to_string(int)
      assert param_logs["uuid1_query_uuid"] == uuid
      assert param_logs["int2_query_int"] == Integer.to_string(int2)
      assert param_logs["int2_query_uuid"] == uuid2
      assert param_logs["uuid2"] == uuid2
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    test "for insert" do
      # Insert values
      int = 1
      uuid = Ecto.UUID.generate()

      # Ensure parameters are complete and in correct order
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
      # Insert values
      int = 1
      uuid = Ecto.UUID.generate()

      # Conflict query
      conflict_int = 0
      conflict_uuid = Ecto.UUID.generate()
      conflict_update = 2

      conflict_query =
        from l in Logging,
          where: l.int == ^conflict_int and l.uuid == ^conflict_uuid,
          update: [set: [int: ^conflict_update]]

      # Ensure parameters are complete and in correct order
      log =
        capture_log(fn ->
          TestRepo.insert!(%Logging{uuid: uuid, int: int},
            on_conflict: conflict_query,
            conflict_target: :bid,
            log: :info
          )
        end)

      param_regex =
        ~r/\[(?<int>.+), \"(?<uuid>.+)\", (?<inserted_at>.+), (?<updated_at>.+), \"(?<bid>.+)\", (?<conflict_update>.+), (?<conflict_int>.+), \"(?<conflict_uuid>.+)\"\]/

      param_logs = Regex.named_captures(param_regex, log)

      # User changes
      assert param_logs["int"] == Integer.to_string(int)
      assert param_logs["uuid"] == uuid
      # Autogenerated changes
      assert param_logs["inserted_at"] =~ @naive_datetime_regex
      assert param_logs["updated_at"] =~ @naive_datetime_regex
      # Filters
      assert param_logs["bid"] =~ @uuid_regex
      # Conflict query parameters
      assert param_logs["conflict_update"] == Integer.to_string(conflict_update)
      assert param_logs["conflict_int"] == Integer.to_string(conflict_int)
      assert param_logs["conflict_uuid"] == conflict_uuid
    end

    test "for update" do
      # Update values
      int = 1
      uuid = Ecto.UUID.generate()
      current = TestRepo.insert!(%Logging{})

      # Ensure parameters are complete and in correct order
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

      # Ensure parameters are complete and in correct order
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
          TestRepo.all(
            from(l in Logging,
              select: type(^"1", :integer),
              where: l.int == ^int and l.uuid == ^uuid
            ),
            log: :info
          )
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
