# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/fixed_cost_limiter.exs

use AtomicBucket.Bench

require AtomicBucket.Bench.FixedCostLimiter, as: FixedCostLimiter
require AtomicBucket.Bench.FixedCostPersLimiter, as: FixedCostPersLimiter

FixedCostLimiter.start_link()
FixedCostPersLimiter.start_link()

IO.puts(
  """
  ###############################################################################################################
  #                                             FixedCostLimiter                                                #
  ###############################################################################################################
  """
)

Benchee.run(
  %{
    "request (literals, reusing ref)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          {_, _, ref} = FixedCostLimiter.request(id, 1, 5_000, 1_000)

          for _ <- 1..(iter_requests() - 1) do
            FixedCostLimiter.request(id, 1, 5_000, 1_000, ref: ref)
          end

        %{size: :monster, bucket_id: id} ->
          {_, _, ref} = FixedCostLimiter.request(id, 1, 5_000_000_000, 2_100_000_000)

          for _ <- 1..(iter_requests() - 1) do
            FixedCostLimiter.request(id, 1, 5_000_000_000, 2_100_000_000, ref: ref)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (literals, persistent)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            FixedCostPersLimiter.request(id, 1, 5_000, 1_000)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            FixedCostPersLimiter.request(id, 1, 5_000_000_000, 2_100_000_000)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (literals, default opts)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            FixedCostLimiter.request(id, 1, 5_000, 1_000)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            FixedCostLimiter.request(id, 1, 5_000_000_000, 2_100_000_000)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, reusing ref)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        {_, _, ref} = FixedCostLimiter.request(id, 1, requests, burst)

        for _ <- 1..(iter_requests() - 1) do
          FixedCostLimiter.request(id, 1, requests, burst, ref: ref)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, persistent)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests() do
          FixedCostPersLimiter.request(id, 1, requests, burst)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, default opts)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests() do
          FixedCostLimiter.request(id, 1, requests, burst)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
  },
  inputs: %{
    "Normal bucket (small atomic)" => %{
      size: :normal,
      requests: 5_000,
      burst: 1_000
    },
    "Monster bucket (big atomic)" => %{
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
