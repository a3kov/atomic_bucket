defmodule AtomicBucketTest do
  use ExUnit.Case
  require AtomicBucket
  import Bitwise
  doctest AtomicBucket

  @multi_buckets %{
    second: {330, 2},
    minute: {3_000, 3},
    hour: {36000, 5}
  }

  setup do
    {:ok, pid} = AtomicBucket.start_link([])

    on_exit(:kill_server, fn -> Process.exit(pid, :test_end) end)

    %{bucket_id: :erlang.unique_integer([:positive])}
  end

  describe "request" do
    test "request allows bursts", %{bucket_id: bucket_id} do
      assert {:allow, 2, _} = AtomicBucket.request(bucket_id, 1, 10, 3)
      assert {:allow, 1, _} = AtomicBucket.request(bucket_id, 1, 10, 3)
      assert {:allow, 0, _} = AtomicBucket.request(bucket_id, 1, 10, 3)
      assert {:deny, _, _} = AtomicBucket.request(bucket_id, 1, 10, 3)
    end

    test "request limits the rate", %{bucket_id: bucket_id} do
      assert {:allow, 0, _} = AtomicBucket.request(bucket_id, 1, 10, 1)
      assert {:deny, _, _} = AtomicBucket.request(bucket_id, 1, 10, 1)
      Process.sleep(90)
      assert {:deny, _, _} = AtomicBucket.request(bucket_id, 1, 10, 1)
      Process.sleep(10)
      assert {:allow, 0, _} = AtomicBucket.request(bucket_id, 1, 10, 1)
    end

    test "with persistent bucket works", %{bucket_id: bucket_id} do
      {:allow, _, bucket_ref} = AtomicBucket.request(bucket_id, 1, 10, 1, persistent: true)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(AtomicBucket, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, AtomicBucket, bucket_id}, nil)
    end

    test "with max capacity works", %{bucket_id: bucket_id} do
      # Use big burst to avoid triggering max window check.
      window = 214_748
      assert {:allow, 9, _} = AtomicBucket.request(bucket_id, window, 1, 10)
    end

    test "with capacity above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        window = 214_749
        AtomicBucket.request(bucket_id, window, 1, 10)
      end
    end

    test "with max window works", %{bucket_id: bucket_id} do
      window = div(1 <<< 31, 1000)
      assert {:allow, 0, _} = AtomicBucket.request(bucket_id, window, 1, 1)
    end

    test "with window above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        window = div(1 <<< 31, 1000) + 1
        AtomicBucket.request(bucket_id, window, 1, 1)
      end
    end
  end

  describe "bucket server" do
    test "cleanup_interval works", %{bucket_id: bucket_id} do
      table = :test_table
      {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 1)
      {:allow, _, bucket_ref} = AtomicBucket.request(bucket_id, 1, 10, 1, table: table)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      Process.sleep(15)
      assert [] = :ets.lookup(table, bucket_id)
      Process.exit(pid, :normal)
    end

    test "persistent bucket cleanup_interval works", %{bucket_id: bucket_id} do
      table = :test_table
      {:ok, pid} = AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 1)

      {:allow, _, bucket_ref} =
        AtomicBucket.request(bucket_id, 1, 10, 1, table: table, persistent: true)

      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.sleep(15)
      assert [] = :ets.lookup(table, bucket_id)
      assert !:persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.exit(pid, :normal)
    end

    test "max_idle_period works", %{bucket_id: bucket_id} do
      table = :test_table

      {:ok, pid} =
        AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 20)

      {:allow, _, bucket_ref} = AtomicBucket.request(bucket_id, 1, 10, 1, table: table)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      Process.sleep(15)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      Process.sleep(15)
      assert [] = :ets.lookup(table, bucket_id)
      Process.exit(pid, :normal)
    end

    test "persistent bucket max_idle_period works", %{bucket_id: bucket_id} do
      table = :test_table

      {:ok, pid} =
        AtomicBucket.start_link(table: table, cleanup_interval: 10, max_idle_period: 20)

      {:allow, _, bucket_ref} =
        AtomicBucket.request(bucket_id, 1, 10, 1, table: table, persistent: true)

      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.sleep(15)
      assert [{^bucket_id, ^bucket_ref}] = :ets.lookup(table, bucket_id)
      assert ^bucket_ref = :persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.sleep(15)
      assert [] = :ets.lookup(table, bucket_id)
      assert !:persistent_term.get({AtomicBucket, table, bucket_id}, nil)
      Process.exit(pid, :normal)
    end

    test "buckets are table-scoped", %{bucket_id: bucket_id} do
      table1 = :test_table1
      table2 = :test_table2

      {:ok, pid1} =
        AtomicBucket.start_link(table: table1, cleanup_interval: 10, max_idle_period: 1)

      {:ok, pid2} =
        AtomicBucket.start_link(table: table2, cleanup_interval: 10, max_idle_period: 1)

      {:allow, _, bucket_ref1} =
        AtomicBucket.request(bucket_id, 1, 10, 1, table: table1, persistent: true)

      {:allow, _, bucket_ref2} =
        AtomicBucket.request(bucket_id, 1, 10, 1, table: table2, persistent: true)

      assert bucket_ref1 != bucket_ref2
      assert [{^bucket_id, ^bucket_ref1}] = :ets.lookup(table1, bucket_id)
      assert [{^bucket_id, ^bucket_ref2}] = :ets.lookup(table2, bucket_id)
      assert ^bucket_ref1 = :persistent_term.get({AtomicBucket, table1, bucket_id}, nil)
      assert ^bucket_ref2 = :persistent_term.get({AtomicBucket, table2, bucket_id}, nil)
      Process.exit(pid1, :normal)
      Process.exit(pid2, :normal)
    end
  end

  describe "raw_request" do
    test "allows bursts", %{bucket_id: bucket_id} do
      # 10 req/s, burst=2
      assert {:allow, 100, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
      assert {:allow, 0, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
      assert {:deny, 0, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
    end

    test "limits the rate", %{bucket_id: bucket_id} do
      # 10 req/s, burst=1
      assert {:allow, 0, _} = AtomicBucket.raw_request(bucket_id, 100, 1, 100)
      assert {:deny, 0, _} = AtomicBucket.raw_request(bucket_id, 100, 1, 100)
      Process.sleep(90)
      {verdict, amount, _} = AtomicBucket.raw_request(bucket_id, 100, 1, 100)
      assert verdict == :deny
      assert is_integer(amount) and amount > 0
      Process.sleep(10)
      assert {:allow, _, _} = AtomicBucket.raw_request(bucket_id, 100, 1, 100)
    end

    test "supports negative and variable cost", %{bucket_id: bucket_id} do
      # 10 req/s, burst=2
      assert {:allow, 100, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
      assert {:allow, 0, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
      assert {:deny, 0, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
      assert {:allow, 200, _} = AtomicBucket.raw_request(bucket_id, 200, 1, -200)
      assert {:allow, 100, _} = AtomicBucket.raw_request(bucket_id, 200, 1, 100)
    end

    test "with max capacity works", %{bucket_id: bucket_id} do
      capacity = AtomicBucket.__max_capacity__()
      tokens = capacity - 1
      assert {:allow, ^tokens, _} = AtomicBucket.raw_request(bucket_id, capacity, 1, 1)
    end

    test "with capacity above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        capacity = AtomicBucket.__max_capacity__() + 1
        AtomicBucket.raw_request(bucket_id, capacity, 1, 1)
      end
    end
  end

  describe "multi_request" do
    test "applies multiple rate limits", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:deny, %{second: {:deny, 1}, minute: {:allow, 1}, hour: {:allow, 3}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 329)

      assert {:allow, %{second: 0, minute: 0, hour: 2}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 330)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 1}, hour: {:allow, 2}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 2999)

      assert {:allow, %{second: 1, minute: 0, hour: 1}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 3000)

      assert {:deny, %{second: {:allow, 1}, minute: {:deny, 2671}, hour: {:allow, 1}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 3329)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 2670}, hour: {:allow, 1}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 3330)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 1}, hour: {:allow, 1}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 5999)

      assert {:allow, %{second: 1, minute: 0, hour: 0}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 6000)

      assert {:deny, %{second: {:allow, 1}, minute: {:deny, 3000}, hour: {:deny, 30000}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 6000)

      assert {:deny, %{second: {:allow, 2}, minute: {:allow, 3}, hour: {:deny, 1}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 35999)

      assert {:allow, %{second: 1, minute: 2, hour: 0}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 36000)
    end

    test "supports zero cost and returns requests for cf=1", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 2, minute: 3, hour: 5}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 0, timer: 0)

      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      # Second got 1 from the timer.
      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 0, timer: 330)
    end

    test "supports refunds", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 300)

      # Second got 1 from the timer and 1 from the refund.
      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, -1, timer: 330)

      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 0, timer: 630)
    end

    test "supports cost factor > 1 and returns scaled numbers", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 0, minute: 0, hour: 1}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 2, timer: 0)

      # The buckets contain 0, 1, 3 with cf=1 after the first request.
      assert {:deny, %{second: {:deny, 660}, minute: {:deny, 3000}, hour: {:allow, 1}}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 2, timer: 0)
    end

    test "supports cost factor < -1 and returns scaled numbers for positive cf", %{
      bucket_id: bucket_id
    } do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, 1, timer: 0)

      # Add tokens for 2 requests, and report how many requests with cf=2 we can make.
      assert {:allow, %{second: 1, minute: 1, hour: 2}, _} =
               AtomicBucket.multi_request(bucket_id, @multi_buckets, -2, timer: 0)
    end

    test "without buckets raises", %{bucket_id: bucket_id} do
      buckets = %{}

      assert_raise ArgumentError, fn ->
        AtomicBucket.multi_request(bucket_id, buckets)
      end
    end

    test "with invalid buckets raises", %{bucket_id: bucket_id} do
      buckets1 = %{a: {1, 2, 3}}
      buckets2 = %{a: {1, :b}}
      buckets3 = %{1 => 2}

      assert_raise ArgumentError, fn ->
        AtomicBucket.multi_request(bucket_id, buckets1)
      end

      assert_raise ArgumentError, fn ->
        AtomicBucket.multi_request(bucket_id, buckets2)
      end

      assert_raise ArgumentError, fn ->
        AtomicBucket.multi_request(bucket_id, buckets3)
      end
    end

    test "with capacity above the max raises", %{bucket_id: bucket_id} do
      low_gcd_buckets =
        %{
          second: {333, 2},
          minute: {3_000, 3},
          hour: {36000, 5}
        }

      assert_raise ArgumentError, fn ->
        AtomicBucket.multi_request(bucket_id, low_gcd_buckets)
      end
    end
  end
end
