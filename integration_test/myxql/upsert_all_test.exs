defmodule Ecto.Integration.UpsertAllTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post

  test "on conflict raise" do
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: :raise)
    assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: :raise))
  end

  test "on conflict ignore" do
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    # First insert succeeds - 1 row inserted
    assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) == {1, nil}
    # Second insert is ignored due to duplicate - 0 rows inserted (INSERT IGNORE behavior)
    assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) == {0, nil}
  end

  test "on conflict ignore with mixed records (some conflicts, some new)" do
    # Insert an existing post
    existing_uuid = "6fa459ea-ee8a-3ca4-894e-db77e160355e"
    existing_post = [title: "existing", uuid: existing_uuid]
    assert TestRepo.insert_all(Post, [existing_post], on_conflict: :nothing) == {1, nil}

    # Now insert a batch with one duplicate and two new records
    new_uuid1 = "7fa459ea-ee8a-3ca4-894e-db77e160355f"
    new_uuid2 = "8fa459ea-ee8a-3ca4-894e-db77e160355a"

    posts = [
      [title: "new post 1", uuid: new_uuid1],     # new - should be inserted
      [title: "duplicate", uuid: existing_uuid],   # duplicate - should be ignored
      [title: "new post 2", uuid: new_uuid2]       # new - should be inserted
    ]

    # With INSERT IGNORE, only 2 rows should be inserted (the non-duplicates)
    assert TestRepo.insert_all(Post, posts, on_conflict: :nothing) == {2, nil}

    # Verify the data - should have 3 posts total (1 existing + 2 new)
    assert length(TestRepo.all(Post)) == 3

    # Verify the existing post was not modified
    [original] = TestRepo.all(from p in Post, where: p.uuid == ^existing_uuid)
    assert original.title == "existing"  # title unchanged

    # Verify new posts were inserted
    assert TestRepo.exists?(from p in Post, where: p.uuid == ^new_uuid1)
    assert TestRepo.exists?(from p in Post, where: p.uuid == ^new_uuid2)
  end

  test "on conflict ignore with all duplicates" do
    # Insert initial posts
    uuid1 = "1fa459ea-ee8a-3ca4-894e-db77e160355e"
    uuid2 = "2fa459ea-ee8a-3ca4-894e-db77e160355e"
    initial_posts = [
      [title: "first", uuid: uuid1],
      [title: "second", uuid: uuid2]
    ]
    assert TestRepo.insert_all(Post, initial_posts, on_conflict: :nothing) == {2, nil}

    # Try to insert all duplicates
    duplicate_posts = [
      [title: "dup1", uuid: uuid1],
      [title: "dup2", uuid: uuid2]
    ]
    # All are duplicates, so 0 rows inserted
    assert TestRepo.insert_all(Post, duplicate_posts, on_conflict: :nothing) == {0, nil}

    # Verify count unchanged
    assert length(TestRepo.all(Post)) == 2
  end

  test "on conflict keyword list" do
    on_conflict = [set: [title: "second"]]
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: on_conflict)

    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {2, nil}
    assert TestRepo.all(from p in Post, select: p.title) == ["second"]
  end

  test "on conflict query and conflict target" do
    on_conflict = from Post, update: [set: [title: "second"]]
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {1, nil}

    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {2, nil}
    assert TestRepo.all(from p in Post, select: p.title) == ["second"]
  end
end
