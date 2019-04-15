defmodule Ecto.Integration.LoggingTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "log entry is sent to telemetry" do
    log = fn event_name, measurement, metadata ->
      assert Enum.at(event_name, -1) == :query
      assert %{result: {:ok, _res}} = metadata
      assert measurement.total_time == measurement.query_time + measurement.decode_time + measurement.queue_time
      send(self(), :logged)
    end

    Process.put(:telemetry, log)
    _ = TestRepo.all(Post)
    assert_received :logged
  end

  test "log entry sent under another event name" do
    log = fn [:custom], measurements, metadata ->
      assert %{result: {:ok, _res}} = metadata
      assert measurements.total_time == measurements.query_time + measurements.decode_time + measurements.queue_time
      send(self(), :logged)
    end

    Process.put(:telemetry, log)
    _ = TestRepo.all(Post, telemetry_event: [:custom])
    assert_received :logged
  end

  test "log entry is not sent to telemetry under nil event name" do
    Process.put(:telemetry, fn _, _ -> raise "never called" end)
    _ = TestRepo.all(Post, telemetry_event: nil)
    refute_received :logged
  end

  test "log entry when some measurements are nil" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             TestRepo.query("BEG", [], log: :error)
           end) =~ "[error]"
  end

  test "log entry with custom log level" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             TestRepo.insert!(%Post{title: "1"}, [log: :error])
           end) =~ "[error]"

    # We cannot assert on the result because it depends on the suite log level
    ExUnit.CaptureLog.capture_log(fn ->
      TestRepo.insert!(%Post{title: "1"}, [log: true])
    end)

    # But this assertion is always true
    assert ExUnit.CaptureLog.capture_log(fn ->
      TestRepo.insert!(%Post{title: "1"}, [log: false])
    end) == ""
  end
end
