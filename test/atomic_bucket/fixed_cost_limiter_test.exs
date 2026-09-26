defmodule AtomicBucket.FixedCostLimiterTest do
  use ExUnit.Case, async: true

  require FixedCostLimiters.DefaultLimiter, as: DefaultLimiter
  require FixedCostLimiters.PersLimiter, as: PersLimiter
  require FixedCostLimiters.CleanupLimiter, as: CleanupLimiter
  require FixedCostLimiters.PersistentCleanup, as: PersistentCleanup
  require FixedCostLimiters.Persistent1, as: Persistent1
  require FixedCostLimiters.Persistent2, as: Persistent2

  setup_all do
    {:ok, pid} = DefaultLimiter.start_link()

    on_exit(:kill_server, fn -> Process.exit(pid, :test_end) end)
  end

  setup do
    %{bucket_id: :erlang.unique_integer([:positive])}
  end

  describe "request" do
    test "allows bursts", %{bucket_id: bucket_id} do
      assert {:allow, 2, _} = DefaultLimiter.request(bucket_id, 1, 10, 3)
      assert {:allow, 1, _} = DefaultLimiter.request(bucket_id, 1, 10, 3)
      assert {:allow, 0, _} = DefaultLimiter.request(bucket_id, 1, 10, 3)
      assert {:deny, _, _} = DefaultLimiter.request(bucket_id, 1, 10, 3)
    end

    test "limits the rate", %{bucket_id: bucket_id} do
      assert {:allow, 0, _} = DefaultLimiter.request(bucket_id, 1, 10, 1, timer: 0)
      assert {:deny, _, _} = DefaultLimiter.request(bucket_id, 1, 10, 1, timer: 0)
      assert {:deny, _, _} = DefaultLimiter.request(bucket_id, 1, 10, 1, timer: 99)
      assert {:allow, 0, _} = DefaultLimiter.request(bucket_id, 1, 10, 1, timer: 100)
    end

    test "with persistent bucket works", %{bucket_id: bucket_id} do
      table = PersLimiter
      PersLimiter.start_link()
      {:allow, _, bucket_ref} = PersLimiter.request(bucket_id, 1, 10, 1)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket_id}, nil)
    end

    test "with max capacity works", %{bucket_id: bucket_id} do
      # Use big burst to avoid triggering max window check.
      burst = AtomicBucket._max_capacity()
      left = burst - 1
      assert {:allow, ^left, _} = DefaultLimiter.request(bucket_id, 1, 1000, burst)
    end

    test "with capacity above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        burst = AtomicBucket._max_capacity()
        DefaultLimiter.request(bucket_id, 1, 1000, burst + 1)
      end
    end

    test "with max window for the limiter works", %{bucket_id: bucket_id} do
      window = 60 * 60 * 24 - 1
      assert {:allow, 0, _} = DefaultLimiter.request(bucket_id, window, 1, 1)
    end

    test "with window above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        window = 60 * 60 * 24
        DefaultLimiter.request(bucket_id, window, 1, 1)
      end
    end
  end

  describe "bucket server" do
    test "cleanup works", %{bucket_id: bucket_id} do
      table = CleanupLimiter
      {:ok, pid} = CleanupLimiter.start_link()
      {:allow, _, bucket_ref} = CleanupLimiter.request(bucket_id, 1, 10, 1)
      Process.sleep(505)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      Process.sleep(500)
      assert [] = :ets.lookup(table, bucket_id)
      Process.exit(pid, :test_end)
    end

    test "persistent bucket cleanup works", %{bucket_id: bucket_id} do
      table = PersistentCleanup
      {:ok, pid} = PersistentCleanup.start_link()
      {:allow, _, bucket_ref} = PersistentCleanup.request(bucket_id, 1, 10, 1)
      Process.sleep(505)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.sleep(500)
      assert [] = :ets.lookup(table, bucket_id)
      assert !:persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.exit(pid, :test_end)
    end

    test "buckets are table-scoped", %{bucket_id: bucket_id} do
      table1 = Persistent1
      table2 = Persistent2
      {:ok, pid1} = Persistent1.start_link()
      {:ok, pid2} = Persistent2.start_link()
      {:allow, _, bucket_ref1} = Persistent1.request(bucket_id, 1, 10, 1)
      {:allow, _, bucket_ref2} = Persistent2.request(bucket_id, 1, 10, 1)
      assert bucket_ref1 != bucket_ref2
      assert [{^bucket_id, ^bucket_ref1}] = :ets.lookup(table1, bucket_id)
      assert [{^bucket_id, ^bucket_ref2}] = :ets.lookup(table2, bucket_id)
      assert ^bucket_ref1 = :persistent_term.get({AtomicBucket, table1, bucket_id}, nil)
      assert ^bucket_ref2 = :persistent_term.get({AtomicBucket, table2, bucket_id}, nil)
      Process.exit(pid1, :test_end)
      Process.exit(pid2, :test_end)
    end
  end
end
