defmodule AtomicBucket.MultiRateLimiterTest do
  use ExUnit.Case, async: true

  require MultiRateLimiters.DefaultLimiter, as: Limiter

  @multi_buckets %{
    second: {330, 2},
    minute: {3_000, 3},
    hour: {36000, 5}
  }

  setup_all do
    {:ok, pid} = Limiter.start_link()

    on_exit(:kill_server, fn -> Process.exit(pid, :test_end) end)
  end

  setup do
    %{bucket_id: :erlang.unique_integer([:positive])}
  end

  describe "multi_request" do
    test "applies multiple rate limits (with details)", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:deny, %{second: {:deny, 1}, minute: {:allow, 1}, hour: {:allow, 3}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 329)

      assert {:allow, %{second: 0, minute: 0, hour: 2}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 330)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 1}, hour: {:allow, 2}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 2999)

      assert {:allow, %{second: 1, minute: 0, hour: 1}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 3000)

      assert {:deny, %{second: {:allow, 1}, minute: {:deny, 2671}, hour: {:allow, 1}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 3329)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 2670}, hour: {:allow, 1}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 3330)

      assert {:deny, %{second: {:allow, 2}, minute: {:deny, 1}, hour: {:allow, 1}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 5999)

      assert {:allow, %{second: 1, minute: 0, hour: 0}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 6000)

      assert {:deny, %{second: {:allow, 1}, minute: {:deny, 3000}, hour: {:deny, 30000}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 6000)

      assert {:deny, %{second: {:allow, 2}, minute: {:allow, 3}, hour: {:deny, 1}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 35999)

      assert {:allow, %{second: 1, minute: 2, hour: 0}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 36000)
    end

    test "applies multiple rate limits", %{bucket_id: bucket_id} do
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 329)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 330)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 2999)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 3000)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 3329)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 3330)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 5999)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 6000)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 6000)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 35999)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 36000)
    end

    test "supports zero cost and returns requests for cf=1 (with details)", %{
      bucket_id: bucket_id
    } do
      assert {:allow, %{second: 2, minute: 3, hour: 5}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 0, timer: 0)

      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      # Second got 1 from the timer.
      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 0, timer: 330)
    end

    test "supports zero cost and returns requests for cf=1", %{bucket_id: bucket_id} do
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 0, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      # Second got 1 from the timer.
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 0, timer: 330)
    end

    test "supports refunds (with details)", %{bucket_id: bucket_id} do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 300)

      # Second got 1 from the timer and 1 from the refund.
      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, -1, timer: 330)

      assert {:allow, %{second: 2, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 0, timer: 630)
    end

    test "supports refunds", %{bucket_id: bucket_id} do
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 300)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, -1, timer: 300)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 300)
    end

    test "supports cost factor > 1 and returns scaled numbers (with details)", %{
      bucket_id: bucket_id
    } do
      assert {:allow, %{second: 0, minute: 0, hour: 1}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 2, timer: 0)

      # The buckets contain 0, 1, 3 with cf=1 after the first request.
      assert {:deny, %{second: {:deny, 660}, minute: {:deny, 3000}, hour: {:allow, 1}}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 2, timer: 0)
    end

    test "supports cost factor > 1", %{bucket_id: bucket_id} do
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 2, timer: 0)
      assert {:deny, _} = Limiter.request(bucket_id, @multi_buckets, 2, timer: 0)
    end

    test "supports cost factor < -1 and returns scaled numbers for positive cf (with details)", %{
      bucket_id: bucket_id
    } do
      assert {:allow, %{second: 1, minute: 2, hour: 4}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      assert {:allow, %{second: 0, minute: 1, hour: 3}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, 1, timer: 0)

      # Add tokens for 2 requests, and report how many requests with cf=2 we can make.
      assert {:allow, %{second: 1, minute: 1, hour: 2}, _} =
               Limiter.request_details(bucket_id, @multi_buckets, -2, timer: 0)
    end

    test "supports cost factor < -1", %{bucket_id: bucket_id} do
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 1, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, -2, timer: 0)
      assert {:allow, _} = Limiter.request(bucket_id, @multi_buckets, 2, timer: 0)
    end

    test "without buckets raises", %{bucket_id: bucket_id} do
      buckets = %{}

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, buckets)
      end
    end

    test "with invalid buckets raises", %{bucket_id: bucket_id} do
      buckets1 = %{a: {1, 2, 3}}
      buckets2 = %{a: {1, :b}}
      buckets3 = %{1 => 2}

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, buckets1)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, buckets2)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, buckets3)
      end
    end

    test "with equal intervals raises", %{bucket_id: bucket_id} do
      equal_intervals1 = %{second: {100, 5}, minute: {3_000, 10}, hour: {100, 6}}
      equal_intervals2 = %{second: {100, 5}, minute: {100, 10}}

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, equal_intervals1)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, equal_intervals2)
      end
    end

    test "with invalid bursts raises", %{bucket_id: bucket_id} do
      low_rate_low_burst1 = %{second: {100, 5}, minute: {3_000, 10}, hour: {36000, 9}}
      low_rate_low_burst2 = %{second: {100, 5}, minute: {3_000, 4}, hour: {36000, 10}}
      low_rate_same_burst1 = %{second: {100, 5}, minute: {3_000, 10}, hour: {36000, 10}}
      low_rate_same_burst2 = %{second: {100, 5}, minute: {3_000, 5}, hour: {36000, 10}}

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, low_rate_low_burst1)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, low_rate_low_burst2)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, low_rate_same_burst1)
      end

      assert_raise ArgumentError, fn ->
        Limiter.request(bucket_id, low_rate_same_burst2)
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
        Limiter.request(bucket_id, low_gcd_buckets)
      end
    end
  end
end
