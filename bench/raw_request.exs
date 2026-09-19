# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/raw_request.exs

use AtomicBucket.Bench

start_link([])

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
        %{size: :normal, bucket_id: id} ->
          {_, _, ref} = raw_request(id, 1_000, 5, 1)

          for _ <- 1..(iter_requests() - 1) do
            raw_request(id, 1_000, 5, 1, ref: ref)
          end

        %{size: :monster, bucket_id: id} ->
          {_, _, ref} = raw_request(id, 2_100_000_000, 1, 1)

          for _ <- 1..(iter_requests() - 1) do
            raw_request(id, 2_100_000_000, 1, 1, ref: ref)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "raw_request (literals, persistent)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            raw_request(id, 1_000, 5, 1, persistent: true)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            raw_request(id, 2_100_000_000, 1, 1, persistent: true)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "raw_request (literals, default opts)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            raw_request(id, 1_000, 5, 1)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            raw_request(id, 2_100_000_000, 1, 1)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "raw_request (non-literals, reusing ref)" => {
      fn %{bucket_id: id, capacity: capacity, refill_ms: refill_ms} ->
        {_, _, ref} = raw_request(id, capacity, refill_ms, 1)

        for _ <- 1..(iter_requests() - 1) do
          raw_request(id, capacity, refill_ms, 1, ref: ref)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "raw_request (non-literals, persistent)" => {
      fn %{bucket_id: id, capacity: capacity, refill_ms: refill_ms} ->
        for _ <- 1..iter_requests() do
          raw_request(id, capacity, refill_ms, 1, persistent: true)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "raw_request (non-literals, default opts)" => {
      fn %{bucket_id: id, capacity: capacity, refill_ms: refill_ms} ->
        for _ <- 1..iter_requests() do
          raw_request(id, capacity, refill_ms, 1)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
  },
  inputs: %{
    "Normal bucket (small atomic)" => %{
      size: :normal,
      capacity: 1_000,
      refill_ms: 5
    },
    "Monster bucket (big atomic)" => %{
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
