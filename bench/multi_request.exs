# This benchmark performs 1_000 rate limit checks in each iteration.
#
# Run it like so:
# mix run bench/multi_request.exs
use AtomicBucket.Bench

start_link([])

IO.puts(
  """
  ###############################################################################################################
  #                                            M U L T I  R E Q U E S T                                         #
  ###############################################################################################################
  """
)

Benchee.run(
  %{
    "multi_request (literals, reusing ref)" => {
      fn
        %{size: :small2, bucket_id: id} ->
          {_, _, ref} = multi_request(id, buckets(:small2))

          for _ <- 1..(iter_requests() - 1) do
            multi_request(id, buckets(:small2), 1, ref: ref)
          end

        %{size: :small3, bucket_id: id} ->
          {_, _, ref} = multi_request(id, buckets(:small3))

          for _ <- 1..(iter_requests() - 1) do
            multi_request(id, buckets(:small3), 1, ref: ref)
          end

        %{size: :big3, bucket_id: id} ->
          {_, _, ref} = multi_request(id, buckets(:big3))

          for _ <- 1..(iter_requests() - 1) do
            multi_request(id, buckets(:big3), 1, ref: ref)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "multi_request (literals, persistent)" => {
      fn
        %{size: :small2, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:small2), 1, persistent: true)
          end

        %{size: :small3, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:small3), 1, persistent: true)
          end

        %{size: :big3, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:big3), 1, persistent: true)
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "multi_request (literals, default opts)" => {
      fn
        %{size: :small2, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:small2))
          end

        %{size: :small3, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:small3))
          end

        %{size: :big3, bucket_id: id} ->
          for _ <- 1..iter_requests() do
            multi_request(id, buckets(:big3))
          end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "multi_request (non-literals, reusing ref)" => {
      fn %{bucket_id: bucket_id, buckets: buckets} ->
        {_, _, ref} = multi_request(bucket_id, buckets)

        for _ <- 1..(iter_requests() - 1) do
          multi_request(bucket_id, buckets, 1, ref: ref)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "multi_request (non-literals, persistent)" => {
      fn %{bucket_id: bucket_id, buckets: buckets} ->
        for _ <- 1..iter_requests() do
          multi_request(bucket_id, buckets, 1, persistent: true)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
    "multi_request (non-literals, default opts)" => {
      fn %{bucket_id: bucket_id, buckets: buckets} ->
        for _ <- 1..iter_requests() do
          multi_request(bucket_id, buckets)
        end
      end,
      before_scenario: &put_unique_bucket_id/1
    },
  },
  inputs: %{
    "2 buckets" => %{
      size: :small2,
      buckets: buckets(:small2),
    },
    "3 buckets (small atomic)" => %{
      size: :small3,
      buckets: buckets(:small3),
    },
    "3 buckets (big atomic)" => %{
      size: :big3,
      buckets: buckets(:big3)
    },
  },
  exclude_outliers: true,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  print: [configuration: false],
  time: 5
)
