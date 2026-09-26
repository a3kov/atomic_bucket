defmodule MultiRateLimiters do
  defmodule DefaultLimiter do
    use AtomicBucket.MultiRateLimiter
  end
end
