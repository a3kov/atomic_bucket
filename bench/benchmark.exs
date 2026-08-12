# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/benchmark.exs

require AtomicBucket

window = 1
requests = 5_000
burst = 1_000
capacity = 1_000
refill_ms = 5
cost = 1
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
      fn bucket ->
        {_, _, ref} = AtomicBucket.request(bucket, 1, 5_000, 1_000)

        for _ <- 1..(iter_requests - 1) do
          AtomicBucket.request(bucket, 1, 5_000, 1_000, ref: ref)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (literals, persistent)" => {
      fn bucket ->
        for _ <- 1..iter_requests do
          AtomicBucket.request(bucket, 1, 5_000, 1_000, persistent: true)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (literals, default opts)" => {
      fn bucket ->
        for _ <- 1..iter_requests do
          AtomicBucket.request(bucket, 1, 5_000, 1_000)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (non-literals, default opts)" => {
      fn bucket ->
        for _ <- 1..iter_requests do
          AtomicBucket.request(bucket, window, requests, burst)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
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
    "raw_request (literals, default opts)" => {
      fn bucket ->
        for _ <- 1..iter_requests do
          AtomicBucket.raw_request(bucket, 1_000, 5, 1)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "raw_request (non-literals, default opts)" => {
      fn bucket ->
        for _ <- 1..iter_requests do
          AtomicBucket.raw_request(bucket, capacity, refill_ms, cost)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
  },
  exclude_outliers: true,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  print: [configuration: false],
  time: 5
)
