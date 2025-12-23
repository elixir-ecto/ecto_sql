# -----------------------------------Goal--------------------------------------
# Compare the implementation of loading raw database data into Ecto structures by
# the different database adapters

# -------------------------------Description-----------------------------------
# Repo.load/2 is an important step of a database query.
# This benchmark tracks performance of loading "raw" data into ecto structures
# Raw data can be in different types (e.g. keyword lists, maps), in this tests
# we benchmark against map inputs

# ----------------------------Factors(don't change)---------------------------
# Different adapters supported by Ecto, each one has its own implementation that
# is tested against different inputs

# ----------------------------Parameters(change)-------------------------------
# Different sizes of raw data(small, medium, big) and different attribute types
# such as UUID, Date and Time fetched from the database and needs to be
# loaded into Ecto structures.

Code.require_file("../../support/setup.exs", __DIR__)

alias Ecto.Bench.User

inputs = %{
  "1. Small 1 Thousand" =>
    1..1_000 |> Stream.map(fn _ -> %{name: "Alice", email: "email@email.com"} end),
  "2. Medium 100 Thousand" =>
    1..100_000 |> Stream.map(fn _ -> %{name: "Alice", email: "email@email.com"} end),
  "3. Big 1 Million" =>
    1..1_000_000 |> Stream.map(fn _ -> %{name: "Alice", email: "email@email.com"} end),
  "4. Time attr" =>
    1..100_000 |> Stream.map(fn _ -> %{name: "Alice", time_attr: ~T[21:25:04.361140]} end),
  "5. Date attr" =>
    1..100_000 |> Stream.map(fn _ -> %{name: "Alice", date_attr: ~D[2018-06-20]} end),
  "6. NaiveDateTime attr" =>
    1..100_000
    |> Stream.map(fn _ ->
      %{name: "Alice", naive_datetime_attr: ~N[2019-06-20 21:32:07.424178]}
    end),
  "7. UUID attr" =>
    1..100_000
    |> Stream.map(fn _ -> %{name: "Alice", uuid: Ecto.UUID.bingenerate()} end)
}

jobs = %{
  "Control" => fn stream -> Enum.each(stream, fn _data -> true end) end,
  "Pg Loader" => fn stream -> Enum.each(stream, &Ecto.Bench.PgRepo.load(User, &1)) end,
  "MyXQL Loader" => fn stream -> Enum.each(stream, &Ecto.Bench.MyXQLRepo.load(User, &1)) end
}

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: Ecto.Bench.Helper.formatters("load")
)
