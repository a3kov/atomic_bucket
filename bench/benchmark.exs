# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/benchmark.exs

require AtomicBucket

window = 1
requests = 5_000
burst = 1_000
parallel = String.to_integer(System.get_env("PARALLEL", "1"))

AtomicBucket.start_link([])

Benchee.run(
  %{
    "AtomicBucket (default)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.request(key, window, requests, burst)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "AtomicBucket (persistent bucket)" => {
      fn key ->
        for _ <- 1..1000 do
          AtomicBucket.request(key, window, requests, burst, persistent: true)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    },
    "AtomicBucket (reusing bucket ref)" => {
      fn key ->
        {_, _, ref} = AtomicBucket.request(key, window, requests, burst)

        for _ <- 1..999 do
          AtomicBucket.request(key, window, requests, burst, ref: ref)
        end
      end,
      before_scenario: fn _ -> :erlang.unique_integer([:positive]) end
    }
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  time: 10,
  parallel: parallel
)
