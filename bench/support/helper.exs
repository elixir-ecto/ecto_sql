defmodule Ecto.Bench.Helper do
  def report_dir, do: System.get_env("BENCHMARKS_OUTPUT_PATH") || "bench/results"

  def formatters(test_name) do
    timestamp = DateTime.now!("Etc/UTC") |> DateTime.to_unix(:second)
    file = Path.join(report_dir(), "#{timestamp}_#{test_name}")
    [
      Benchee.Formatters.Console,
      {Benchee.Formatters.JSON, file: "#{file}.json"},
      {Benchee.Formatters.HTML, file: "#{file}.html", auto_open: false}
    ]
  end
end
