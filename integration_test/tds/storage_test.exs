Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case

  @moduletag :capture_log

  alias Ecto.Adapters.Tds

  def params do
    url = Application.get_env(:ecto_sql, :tds_test_url) <> "/storage_mgt"
    [log: false] ++ Ecto.Repo.Supervisor.parse_url(url)
  end

  def wrong_params() do
    Keyword.merge params(),
      [username: "randomuser",
       password: "password1234"]
  end

  test "storage up (twice in a row)" do
    assert :ok == Tds.storage_up(params())
    assert {:error, :already_up} == Tds.storage_up(params())
  after
    Tds.storage_down(params())
  end

  test "storage down (twice in a row)" do
    assert :ok == Tds.storage_up(params())
    assert :ok == Tds.storage_down(params())
    assert {:error, :already_down} == Tds.storage_down(params())
  end

  test "storage up and down (wrong credentials)" do
    refute :ok == Tds.storage_up(wrong_params())
    assert :ok == Tds.storage_up(params())
    refute :ok == Tds.storage_down(wrong_params())
  after
    Tds.storage_down(params())
  end

  defmodule Migration do
    use Ecto.Migration
    def change, do: :ok
  end

  test "storage status is up when database is created" do
    Tds.storage_up(params())
    assert :up == Tds.storage_status(params())
  after
    Tds.storage_down(params())
  end

  test "storage status is down when database is not created" do
    Tds.storage_up(params())
    Tds.storage_down(params())
    assert :down == Tds.storage_status(params())
  end

  test "storage status is an error when wrong credentials are passed" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             assert {:error, _} = Tds.storage_status(wrong_params())
           end) =~ ~r"Login failed for user 'randomuser'"
  end
end
