defmodule AtomicBucketTest do
  use ExUnit.Case
  require AtomicBucket
  import Bitwise
  doctest AtomicBucket

  setup do
    {:ok, pid} = AtomicBucket.start_link([])

    on_exit(:kill_server, fn -> Process.exit(pid, :normal) end)

    %{bucket: :erlang.unique_integer([:positive])}
  end

  test "allows bursts", %{bucket: bucket} do
    assert {:allow, 2, _} = AtomicBucket.request(bucket, 1, 10, 3)
    assert {:allow, 1, _} = AtomicBucket.request(bucket, 1, 10, 3)
    assert {:allow, 0, _} = AtomicBucket.request(bucket, 1, 10, 3)
    assert {:deny, _, _} = AtomicBucket.request(bucket, 1, 10, 3)
  end

  test "limits the rate", %{bucket: bucket} do
    assert {:allow, 0, _} = AtomicBucket.request(bucket, 1, 10, 1)
    assert {:deny, _, _} = AtomicBucket.request(bucket, 1, 10, 1)
    Process.sleep(90)
    assert {:deny, _, _} = AtomicBucket.request(bucket, 1, 10, 1)
    Process.sleep(10)
    assert {:allow, 0, _} = AtomicBucket.request(bucket, 1, 10, 1)
  end

  test "persistent bucket works", %{bucket: bucket} do
    {:allow, _, bucket_ref} = AtomicBucket.request(bucket, 1, 10, 1, persistent: true)
    assert [{^bucket, ^bucket_ref}] = :ets.lookup(AtomicBucket, bucket)
    assert ^bucket_ref = :persistent_term.get({AtomicBucket, AtomicBucket, bucket}, nil)
  end

  test "request with max capacity works", %{bucket: bucket} do
    # Use big burst to avoid triggering max window check.
    window = 214_748
    assert {:allow, 9, _} = AtomicBucket.request(bucket, window, 1, 10)
  end

  test "request with capacity above the max raises", %{bucket: bucket} do
    assert_raise ArgumentError, fn ->
      window = 214_749
      AtomicBucket.request(bucket, window, 1, 10)
    end
  end

  test "request with max window works", %{bucket: bucket} do
    window = div(1 <<< 31, 1000)
    assert {:allow, 0, _} = AtomicBucket.request(bucket, window, 1, 1)
  end

  test "request with window above the max raises", %{bucket: bucket} do
    assert_raise ArgumentError, fn ->
      window = div(1 <<< 31, 1000) + 1
      AtomicBucket.request(bucket, window, 1, 1)
    end
  end

  test "cleanup_interval works", %{bucket: bucket} do
    table = :test_table
    {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 1)
    {:allow, _, bucket_ref} = AtomicBucket.request(bucket, 1, 10, 1, table: table)
    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    Process.sleep(15)
    assert [] = :ets.lookup(table, bucket)
    Process.exit(pid, :normal)
  end

  test "persistent bucket cleanup_interval works", %{bucket: bucket} do
    table = :test_table
    {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 1)

    {:allow, _, bucket_ref} =
      AtomicBucket.request(bucket, 1, 10, 1, table: table, persistent: true)

    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket}, nil)
    Process.sleep(15)
    assert [] = :ets.lookup(table, bucket)
    assert !:persistent_term.get({AtomicBucket, table, bucket}, nil)
    Process.exit(pid, :normal)
  end

  test "max_idle_period works", %{bucket: bucket} do
    table = :test_table
    {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 20)
    {:allow, _, bucket_ref} = AtomicBucket.request(bucket, 1, 10, 1, table: table)
    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    Process.sleep(15)
    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    Process.sleep(15)
    assert [] = :ets.lookup(table, bucket)
    Process.exit(pid, :normal)
  end

  test "persistent bucket max_idle_period works", %{bucket: bucket} do
    table = :test_table
    {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 20)

    {:allow, _, bucket_ref} =
      AtomicBucket.request(bucket, 1, 10, 1, table: table, persistent: true)

    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket}, nil)
    Process.sleep(15)
    assert [{^bucket, ^bucket_ref}] = :ets.lookup(table, bucket)
    assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket}, nil)
    Process.sleep(15)
    assert [] = :ets.lookup(table, bucket)
    assert !:persistent_term.get({AtomicBucket, table, bucket}, nil)
    Process.exit(pid, :normal)
  end

  test "buckets are table-scoped", %{bucket: bucket} do
    table1 = :test_table1
    table2 = :test_table2
    {:ok, pid1} = AtomicBucket.start_link(table: table1, cleanup_interval: 10, max_idle_period: 1)
    {:ok, pid2} = AtomicBucket.start_link(table: table2, cleanup_interval: 10, max_idle_period: 1)

    {:allow, _, bucket_ref1} =
      AtomicBucket.request(bucket, 1, 10, 1, table: table1, persistent: true)

    {:allow, _, bucket_ref2} =
      AtomicBucket.request(bucket, 1, 10, 1, table: table2, persistent: true)

    assert bucket_ref1 != bucket_ref2
    assert [{^bucket, ^bucket_ref1}] = :ets.lookup(table1, bucket)
    assert [{^bucket, ^bucket_ref2}] = :ets.lookup(table2, bucket)
    assert ^bucket_ref1 = :persistent_term.get({AtomicBucket, table1, bucket}, nil)
    assert ^bucket_ref2 = :persistent_term.get({AtomicBucket, table2, bucket}, nil)
    Process.exit(pid1, :normal)
    Process.exit(pid2, :normal)
  end
end
