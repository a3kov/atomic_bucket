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
parallel = String.to_integer(System.get_env("PARALLEL", "1"))

AtomicBucket.start_link([])

Benchee.run(
  %{
    "request (non-literals, default opts)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.request(key, window, requests, burst)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (literals, default opts)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.request(key, 1, 5_000, 1_000)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (literals, persistent)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.request(key, 1, 5_000, 1_000, persistent: true)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "request (literals, reusing ref)" => {
      fn key ->
        {_, _, ref} = AtomicBucket.request(key, window, requests, burst)

        for _ <- 1..999 do
          AtomicBucket.request(key, 1, 5_000, 1_000, ref: ref)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "raw_request (non-literals, default opts)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.raw_request(key, capacity, refill_ms, cost)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "raw_request (literals, default opts)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.raw_request(key, 1_000, 5, 1)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  time: 5,
  parallel: parallel
)
