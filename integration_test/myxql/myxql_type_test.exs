defmodule Ecto.Integration.MyXQLTypeTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)
  alias Ecto.Integration.TestRepo
  import Ecto.Query

  defmodule Bool do
    use Ecto.Schema

    schema "bits" do
      field :bit, :boolean
    end
  end

  test "bit" do
    TestRepo.insert_all("bits", [[bit: <<1::1>>], [bit: <<0::1>>]])

    assert TestRepo.all(from(b in "bits", select: b.bit, order_by: [desc: :bit])) == [
             <<1::1>>,
             <<0::1>>
           ]
  end

  test "bit as boolean" do
    TestRepo.insert_all("bits", [[bit: <<1::1>>], [bit: <<0::1>>]])

    assert TestRepo.all(from(b in Bool, select: b.bit, order_by: [desc: :bit])) == [
             true,
             false
           ]
  end
end
