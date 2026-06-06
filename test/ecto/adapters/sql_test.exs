defmodule Ecto.Adapters.SQLTest.FakeError do
  defexception [:type, :name, :message]
end

defmodule Ecto.Adapters.SQLTest.FakeConnection do
  alias Ecto.Adapters.SQLTest.FakeError

  def to_constraints(%FakeError{type: :unique, name: name}, _opts), do: [unique: name]
  def to_constraints(%FakeError{type: :check, name: name}, _opts), do: [check: name]
  def to_constraints(_err, _opts), do: []
end

defmodule Ecto.Adapters.SQLTest.CustomHandler do
  alias Ecto.Adapters.SQLTest.{FakeError, FakeConnection}

  def to_constraints(%FakeError{type: :other, name: name}, _opts), do: [exclusion: name]
  def to_constraints(err, opts), do: FakeConnection.to_constraints(err, opts)
end

defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQLTest.{FakeError, FakeConnection, CustomHandler}

  @adapter_meta %{sql: FakeConnection}
  @unique_err %FakeError{type: :unique, name: "users_email_index", message: "unique violation"}
  @custom_err %FakeError{type: :other, name: "cannot_overlap", message: "overlap"}

  defp to_constraints(err, opts \\ []) do
    Ecto.Adapters.SQL.to_constraints(@adapter_meta, err, opts, source: "test")
  end

  describe "to_constraints/4" do
    test "uses the adapter connection's to_constraints/2 by default" do
      assert to_constraints(@unique_err) == [unique: "users_email_index"]
    end

    test "returns empty list when no constraint matches the default handler" do
      assert to_constraints(@custom_err) == []
    end

    test "custom handler handles errors the default handler wouldn't" do
      assert to_constraints(@custom_err, constraint_handler: &CustomHandler.to_constraints/2) ==
               [exclusion: "cannot_overlap"]
    end

    test "custom handler can fall back to the default handler" do
      assert to_constraints(@unique_err, constraint_handler: &CustomHandler.to_constraints/2) ==
               [unique: "users_email_index"]
    end

    test "passes error options to the constraint handler" do
      handler = fn _err, opts ->
        send(self(), {:handler_opts, opts})
        []
      end

      to_constraints(@custom_err, constraint_handler: handler)
      assert_received {:handler_opts, [source: "test"]}
    end
  end
end
