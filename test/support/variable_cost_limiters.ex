defmodule VariableCostLimiters do
  defmodule DefaultLimiter do
    use AtomicBucket.VariableCostLimiter
  end
end
