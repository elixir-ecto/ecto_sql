defmodule Ecto.Integration.Migration2 do
  use Ecto.Migration

  def change do
    alter table("posts") do
      modify :text, :string, size: :max
    end
  end
end
