defmodule AtomicBucket.Bench do
  @moduledoc false

  defmodule FixedCostLimiter do
    @moduledoc false
    use AtomicBucket.FixedCostLimiter
  end

  defmodule FixedCostPersLimiter do
    @moduledoc false
    use AtomicBucket.FixedCostLimiter,
      persistent: true
  end

  defmodule VariableCostLimiter do
    @moduledoc false
    use AtomicBucket.VariableCostLimiter
  end

  defmodule VariableCostPersLimiter do
    @moduledoc false
    use AtomicBucket.VariableCostLimiter,
      persistent: true
  end

  defmodule MultiRateLimiter do
    @moduledoc false
    use AtomicBucket.MultiRateLimiter
  end

  defmodule MultiRatePersLimiter do
    @moduledoc false
    use AtomicBucket.MultiRateLimiter,
      persistent: true
  end

  defmacro __using__(_opts) do
    quote do
      require AtomicBucket.Bench
      import AtomicBucket.Bench
    end
  end

  defmacro iter_requests() do
    quote do: 1000
  end

  def put_unique_bucket_id(inputs) do
    Map.put(inputs, :bucket_id, :erlang.unique_integer([:positive]))
  end

  defmacro buckets(:small2) do
    quote do
      %{second: {333, 1}, minute: {3_000, 10}}
    end
  end

  defmacro buckets(:small3) do
    quote do
      %{second: {500, 3}, minute: {3_000, 10}, hour: {36_000, 30}}
    end
  end

  defmacro buckets(:big3) do
    quote do
      %{second: {330, 2}, minute: {3_000, 7}, hour: {60000, 30}}
    end
  end
end
