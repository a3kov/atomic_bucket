defmodule FixedCostLimiters do
  defmodule DefaultLimiter do
    use AtomicBucket.FixedCostLimiter
  end

  defmodule PersLimiter do
    use AtomicBucket.FixedCostLimiter,
      persistent: true
  end

  defmodule CleanupLimiter do
    use AtomicBucket.FixedCostLimiter,
      cleanup_interval: 500,
      max_idle_period: 1001
  end

  defmodule PersistentCleanup do
    use AtomicBucket.FixedCostLimiter,
      cleanup_interval: 500,
      max_idle_period: 1001,
      persistent: true
  end

  defmodule Persistent1 do
    use AtomicBucket.FixedCostLimiter,
      cleanup_interval: 1000,
      max_idle_period: 2000,
      persistent: true
  end

  defmodule Persistent2 do
    use AtomicBucket.FixedCostLimiter,
      cleanup_interval: 1000,
      max_idle_period: 2000,
      persistent: true
  end
end
