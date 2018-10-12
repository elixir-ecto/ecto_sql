defmodule Ecto.Integration.LoggingTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "log entry logged on query" do
    log = fn latency, entry ->
      assert %Ecto.LogEntry{result: {:ok, _}} = entry
      assert latency == entry.query_time + entry.decode_time + entry.queue_time
      send(self(), :logged)
    end

    Process.put(:telemetry, log)
    _ = TestRepo.all(Post)
    assert_received :logged
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
