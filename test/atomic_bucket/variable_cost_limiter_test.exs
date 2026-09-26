defmodule AtomicBucket.VariableCostLimiterTest do
  use ExUnit.Case, async: true

  require VariableCostLimiters.DefaultLimiter, as: Limiter

  setup_all do
    {:ok, pid} = Limiter.start_link()

    on_exit(:kill_server, fn -> Process.exit(pid, :test_end) end)
  end

  setup do
    %{bucket_id: :erlang.unique_integer([:positive])}
  end

  describe "request" do
    test "allows bursts", %{bucket_id: bucket_id} do
      # 10 req/s, burst=2
      assert {:allow, 100, _} = Limiter.request(bucket_id, 200, 1, 100)
      assert {:allow, 0, _} = Limiter.request(bucket_id, 200, 1, 100)
      assert {:deny, 0, _} = Limiter.request(bucket_id, 200, 1, 100)
    end

    test "limits the rate", %{bucket_id: bucket_id} do
      # 10 req/s, burst=1
      assert {:allow, 0, _} = Limiter.request(bucket_id, 100, 1, 100, timer: 0)
      assert {:deny, 0, _} = Limiter.request(bucket_id, 100, 1, 100, timer: 0)
      assert {:deny, 99, _} = Limiter.request(bucket_id, 100, 1, 100, timer: 99)
      assert {:allow, 0, _} = Limiter.request(bucket_id, 100, 1, 100)
    end

    test "supports negative and variable cost", %{bucket_id: bucket_id} do
      # 10 req/s, burst=2
      assert {:allow, 100, _} = Limiter.request(bucket_id, 200, 1, 100)
      assert {:allow, 0, _} = Limiter.request(bucket_id, 200, 1, 100)
      assert {:deny, 0, _} = Limiter.request(bucket_id, 200, 1, 100)
      assert {:allow, 200, _} = Limiter.request(bucket_id, 200, 1, -200)
      assert {:allow, 100, _} = Limiter.request(bucket_id, 200, 1, 100)
    end

    test "with max capacity works", %{bucket_id: bucket_id} do
      capacity = AtomicBucket._max_capacity()
      tokens = capacity - 1
      assert {:allow, ^tokens, _} = Limiter.request(bucket_id, capacity, 1, 1)
    end

    test "with capacity above the max raises", %{bucket_id: bucket_id} do
      assert_raise ArgumentError, fn ->
        capacity = AtomicBucket._max_capacity() + 1
        Limiter.request(bucket_id, capacity, 1, 1)
      end
    end
  end
end
