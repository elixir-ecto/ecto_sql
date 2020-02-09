defmodule Ecto.Integration.Migration2 do
  use Ecto.Migration

  def change do
    alter table("posts") do
      modify :text, :string, size: :max
    end

#    drop unique_index(:permalinks, [:post_id])
#    create unique_index(:permalinks, [:post_id], where: "[post_id] IS NOT NULL")
  end
end
