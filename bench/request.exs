# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/request.exs

use AtomicBucket.Bench

start_link([])

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
        %{size: :normal, bucket_id: id} ->
          {_, _, ref} = request(id, 1, 5_000, 1_000)

          for _ <- 1..(iter_requests() - 1) do
            request(id, 1, 5_000, 1_000, ref: ref)
          end

        %{size: :monster, bucket_id: id} ->
          {_, _, ref} = request(id, 1, 5_000_000_000, 2_100_000_000)

          for _ <- 1..(iter_requests() - 1) do
            request(id, 1, 5_000_000_000, 2_100_000_000, ref: ref)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (literals, persistent)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            request(id, 1, 5_000, 1_000, persistent: true)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            request(id, 1, 5_000_000_000, 2_100_000_000, persistent: true)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (literals, default opts)" => {
      fn
        %{size: :normal, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            request(id, 1, 5_000, 1_000)
          end

        %{size: :monster, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            request(id, 1, 5_000_000_000, 2_100_000_000)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, reusing ref)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        {_, _, ref} = request(id, 1, requests, burst)

        for _ <- 1..(iter_requests() - 1) do
          request(id, 1, requests, burst, ref: ref)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, persistent)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests() do
          request(id, 1, requests, burst, persistent: true)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "request (non-literals, default opts)" => {
      fn %{bucket_id: id, requests: requests, burst: burst} ->
        for _ <- 1..iter_requests() do
          request(id, 1, requests, burst)
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
