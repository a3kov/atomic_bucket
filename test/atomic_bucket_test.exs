defmodule AtomicBucketTest do
  use ExUnit.Case, async: true
  doctest AtomicBucket

  defmodule TestLimiter do
  end

  describe "validated_rate_limiter_opts/2" do
    test "raises with invalid table" do
      assert_raise ArgumentError, fn ->
        AtomicBucket.validated_rate_limiter_opts([table: 1], TestLimiter)
      end

      assert_raise ArgumentError, fn ->
        AtomicBucket.validated_rate_limiter_opts([table: "test"], TestLimiter)
      end
    end

    test "works with cleanup_interval and cleanup_interval below the limit" do
      opts = [
        cleanup_interval: :timer.hours(24 * 23),
        max_idle_period: :timer.hours(24 * 24)
      ]

      AtomicBucket.validated_rate_limiter_opts(opts, TestLimiter)
    end

    test "raises with max_idle_period above the limit" do
      assert_raise ArgumentError, fn ->
        opts = [
          cleanup_interval: :timer.hours(24 * 24),
          max_idle_period: :timer.hours(24 * 25)
        ]

        AtomicBucket.validated_rate_limiter_opts(opts, TestLimiter)
      end
    end

    test "raises with cleanup_interval > max_idle_period" do
      assert_raise ArgumentError, fn ->
        opts = [
          cleanup_interval: :timer.hours(2),
          max_idle_period: :timer.hours(1)
        ]

        AtomicBucket.validated_rate_limiter_opts(opts, TestLimiter)
      end
    end

    test "raises with invalid persistent" do
      assert_raise ArgumentError, fn ->
        AtomicBucket.validated_rate_limiter_opts([persistent: 1], TestLimiter)
      end

      assert_raise ArgumentError, fn ->
        AtomicBucket.validated_rate_limiter_opts([persistent: :on], TestLimiter)
      end
    end
  end
end
