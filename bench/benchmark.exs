# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/benchmark.exs

require AtomicBucket

iter_requests = 1_000

AtomicBucket.start_link([])

IO.puts(
  """
  ###############################################################################################################
  #                                                R E Q U E S T                                                #
  ###############################################################################################################
  """
)
Benchee.run(
  %{
    "request (literals, reusing ref)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          {_, _, ref} = AtomicBucket.request(bucket, 1, 5_000, 1_000)

          for _ <- 1..(iter_requests - 1) do
            AtomicBucket.request(bucket, 1, 5_000, 1_000, ref: ref)
          end

        %{size: :monster, bucket: bucket} ->
          {_, _, ref} = AtomicBucket.request(bucket, 1, 5_000_000_000, 2_100_000_000)

          for _ <- 1..(iter_requests - 1) do
            AtomicBucket.request(bucket, 1, 5_000_000_000, 2_100_000_000, ref: ref)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "request (literals, persistent)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.request(bucket, 1, 5_000, 1_000, persistent: true)
          end

        %{size: :monster, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.request(bucket, 1, 5_000_000_000, 2_100_000_000, persistent: true)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "request (literals, default opts)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.request(bucket, 1, 5_000, 1_000)
          end

        %{size: :monster, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.request(bucket, 1, 5_000_000_000, 2_100_000_000)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "request (non-literals, reusing ref)" => {
      fn %{bucket: bucket, requests: requests, burst: burst} ->
        {_, _, ref} = AtomicBucket.request(bucket, 1, requests, burst)

        for _ <- 1..(iter_requests - 1) do
          AtomicBucket.request(bucket, 1, requests, burst, ref: ref)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "request (non-literals, persistent)" => {
      fn %{bucket: bucket, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests do
          AtomicBucket.request(bucket, 1, requests, burst, persistent: true)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "request (non-literals, default opts)" => {
      fn %{bucket: bucket, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests do
          AtomicBucket.request(bucket, 1, requests, burst)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
  },
  inputs: %{
    "Normal bucket" => %{
      size: :normal,
      requests: 5_000,
      burst: 1_000
    },
    "Monster bucket (extreme size)" => %{
      size: :monster,
      requests: 5_000_000_000,
      burst: 2_100_000_000
    }
  },
  exclude_outliers: true,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  print: [configuration: false],
  time: 5
)

IO.puts(
  """

  ###############################################################################################################
  #                                              R A W  R E Q U E S T                                           #
  ###############################################################################################################
  """
)

Benchee.run(
  %{
    "raw_request (literals, reusing ref)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          {_, _, ref} = AtomicBucket.raw_request(bucket, 1_000, 5, 1)

          for _ <- 1..(iter_requests - 1) do
            AtomicBucket.raw_request(bucket, 1_000, 5, 1, ref: ref)
          end

        %{size: :monster, bucket: bucket} ->
          {_, _, ref} = AtomicBucket.raw_request(bucket, 2_100_000_000, 1, 1)

          for _ <- 1..(iter_requests - 1) do
            AtomicBucket.raw_request(bucket, 2_100_000_000, 1, 1, ref: ref)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "raw_request (literals, persistent)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.raw_request(bucket, 1_000, 5, 1, persistent: true)
          end

        %{size: :monster, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.raw_request(bucket, 2_100_000_000, 1, 1, persistent: true)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "raw_request (literals, default opts)" => {
      fn
        %{size: :normal, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.raw_request(bucket, 1_000, 5, 1)
          end

        %{size: :monster, bucket: bucket} ->
          for _ <- 1..iter_requests do
            AtomicBucket.raw_request(bucket, 2_100_000_000, 1, 1)
          end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "raw_request (non-literals, reusing ref)" => {
      fn %{bucket: bucket, capacity: capacity, refill_ms: refill_ms} ->
        {_, _, ref} = AtomicBucket.raw_request(bucket, capacity, refill_ms, 1)

        for _ <- 1..(iter_requests - 1) do
          AtomicBucket.raw_request(bucket, capacity, refill_ms, 1, ref: ref)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "raw_request (non-literals, persistent)" => {
      fn %{bucket: bucket, capacity: capacity, refill_ms: refill_ms} ->
        for _ <- 1..iter_requests do
          AtomicBucket.raw_request(bucket, capacity, refill_ms, 1, persistent: true)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
    "raw_request (non-literals, default opts)" => {
      fn %{bucket: bucket, capacity: capacity, refill_ms: refill_ms} ->
        for _ <- 1..iter_requests do
          AtomicBucket.raw_request(bucket, capacity, refill_ms, 1)
        end
      end,
      before_scenario: fn inputs -> Map.put(inputs, :bucket, :erlang.unique_integer([:positive])) end
    },
  },
  inputs: %{
    "Normal bucket" => %{
      size: :normal,
      capacity: 1_000,
      refill_ms: 5
    },
    "Monster bucket (extreme size)" => %{
      size: :monster,
      capacity: 2_100_000_000,
      refill_ms: 1
    }
  },
  exclude_outliers: true,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  print: [configuration: false],
  time: 5
)
